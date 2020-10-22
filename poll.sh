#!/bin/bash
# ensure running bash
if ! [ -n "$BASH_VERSION" ];then
    echo "this is not bash, calling self with bash....";
    SCRIPT=$(readlink -f "$0")
    /bin/bash $SCRIPT
    exit;
fi

# cd to script dir to have correct pwd set
cd "$(dirname "$0")";

# color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color


# uncomment to debug
# set -x

# builds desired image using tag name and restarts containers
rebuild() {
  repoType=$1
  REPO="${REPOS[$1]}"
  mkdir docker -p
  dockerfile $repoType > docker/Dockerfile
  if docker build -t $REPO - < docker/Dockerfile ; then
    stopdock $repoType
    rundock $repoType
  fi
}

# checks if container is running, returns true if not
is_down() {
  container_name="${REPOS[$1]}"
  if [ "$(docker ps -q -f name=$container_name)" ]; then
    return 1
  else
    return 0
  fi
}

# here docker runs for all containers are kept
rundock() {
  NAME="${REPOS[$1]}"
  printf "Starting $1 container...\n"
  if [ $1 = 'front' ]; then
    notify 'Starting FRONT container'
    export $(cat $(pwd)/env_front | xargs)
    cmd="docker run --rm -d \
      --env-file $(pwd)/env_front \
      --mount type=bind,source=/var/log/fpm-error.log,target=/var/log/error.log \
      --mount type=bind,source=/var/log/fpm-access.log,target=/var/log/access.log \
      --mount type=bind,source="$(pwd)"/www.conf,target=/usr/local/etc/php-fpm.d/www.conf \
      -p 9000:9000 \
      --name $NAME $NAME"
    postCmd="docker cp $NAME:/var/www /var/www/front"
  elif [ $1 = 'back' ]; then
    notify 'Starting BACK container'
    export $(cat $(pwd)/env_back | xargs)
    cmd="docker run --rm -d \
      --env-file $(pwd)/env_back \
      --mount type=bind,source=/var/log/backend-app.log,target=/var/log/backend-app.log \
      --add-host=postgres:172.17.0.1 \
      -p 8080:8080 \
      -p 8443:8443 \
      --name $NAME $NAME"
    postCmd="echo '' > /dev/null"
  elif [ $1 = 'admin' ]; then
    notify 'Starting ADMIN container'
    export $(cat $(pwd)/env_front | xargs)
    cmd="docker run --rm -d \
      --env-file $(pwd)/env_front \
      --mount type=bind,source=/var/log/fpm-admin-error.log,target=/var/log/error.log \
      --mount type=bind,source=/var/log/fpm-admin-access.log,target=/var/log/access.log \
      --mount type=bind,source="$(pwd)"/www.conf,target=/usr/local/etc/php-fpm.d/www.conf \
      -p 9900:9000 \
      --name $NAME $NAME"
    postCmd="docker cp $NAME:/var/www /var/www/admin"
  else
    err 'Unexpected type'
  fi

  printf "$GREEN $cmd $NC\n"
  ${cmd}
  printf "\n"
  printf "$GREEN $postCmd $NC\n"
  ${postCmd}
  printf "\n"
}

stopdock() {
  NAME="${REPOS[$1]}"
  printf "Stopping old containers...\n"
  docker stop $NAME
  docker rm $NAME
}

dockerfile() {
  REPO="${REPOS[$1]}"
  echo "FROM $REGISTRY/$REPO"
}

notify() {
  /root/telegram.sh/telegram "$1" 2> /dev/null
}

# compares local and registry images
update_exists() {
  REPO="${REPOS[$1]}"
#  LATEST="`wget -qO- http://$REGISTRY/v2/$REPO/tags/list`"
#  LATEST=`echo $LATEST | sed "s/{//g" | sed "s/}//g" | sed 's/.*tags"://' | sed "s/\"//g" | cut -d ' ' -f2`
#
#  RUNNING=`docker inspect "$REGISTRY/$REPO" | grep Id | sed "s/\"//g" | sed "s/,//g" |  tr -s ' ' | cut -d ' ' -f3`

  LATEST=$(curl --silent -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "http://$REGISTRY/v2/$REPO/manifests/latest" | jq -r '.config.digest')
  RUNNING=$(docker images -q --no-trunc $REPO:latest)

  if [ -z "$LATEST" ]; then
    return 1
  fi

  if [ "$RUNNING" == "$LATEST" ];then
    return 1
  else
    return 0
  fi
}

title() {
  sleep 0.5
  printf "\n$GREEN ----------------------------------------------------------\n| \
    $1...\n ----------------------------------------------------------$NC\n"
}

err() {
  printf "$RED\nERROR: $1 $NC\n"
}





######
# Main execution starts from here
######

REGISTRY="35.185.239.138:5000"
declare -A REPOS
REPOS['front']='front-suroo-kg'
REPOS['back']='back-suroo-kg'
REPOS['admin']='admin-suroo-kg'

# update local images before check
dt=$(date '+%d/%m/%Y %H:%M:%S');
printf "\n===== $dt ====="
title "Checking image updates"
docker pull $REGISTRY/${REPOS['front']}
docker pull $REGISTRY/${REPOS['back']}
docker pull $REGISTRY/${REPOS['admin']}


title 'Checking if containers are up and starting if not'
if is_down 'front'; then
  rundock 'front'
fi
if is_down 'back'; then
  rundock 'back'
fi
if is_down 'admin'; then
  rundock 'admin'
fi


title 'Checking container updates'
if update_exists 'front' ; then
  notify 'FRONT update in progress...'
  title 'Rebuilding front'
  rebuild 'front'
else
  echo 'Front is latest version'
fi

if update_exists "back" ; then
  notify 'BACK update in progress...'
  title 'Rebuilding back'
  rebuild 'back'
else
  echo 'Back is latest version'
fi

if update_exists "admin" ; then
  notify 'ADMIN update in progress...'
  title 'Rebuilding admin'
  rebuild 'admin'
else
  echo 'Admin is latest version'
fi


title 'Checking if containers are up again'
if is_down 'front'; then
  err 'Front container is down'
  notify 'ACHTUNG! FRONT container is down'
else
  printf "Front:$GREEN ✓ UP $NC\n";
fi

if is_down 'back'; then
  err 'Back container is down'
  notify 'ACHTUNG! BACK container is down'
else
  printf "Back: $GREEN ✓ UP $NC\n";
fi

if is_down 'admin'; then
  err 'Admin container is down'
  notify 'ACHTUNG! ADMIN container is down'
else
  printf "Admin: $GREEN ✓ UP $NC\n";
fi
