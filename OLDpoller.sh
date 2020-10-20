#!/bin/bash
# ensure running bash
if ! [ -n "$BASH_VERSION" ];then
    echo "this is not bash, calling self with bash....";
    SCRIPT=$(readlink -f "$0")
    /bin/bash $SCRIPT
    exit;
fi

# uncomment to debug
# set -x

pull() {
  repoType=$1
  REPO="${REPOS[$1]}"
  mkdir deploy -p
  dockerfile $repoType > deploy/Dockerfile
  if docker build -t $REPO - < deploy/Dockerfile ; then
    echo "Stopping old containers...\n"
    docker rm $(docker stop $(docker ps -a -q --filter ancestor=$REPO --format="{{.ID}}"))  
    echo "Starting $1 container...\n"
    docker run -it -d $REPO
    docker exec -ti $REPO $(exec_command repoType)
  fi
}

exec_command() {
  REPO="${REPOS[$1]}"
  echo $REPO
  echo "!!!"
  echo $1
  echo "."
}

dockerfile() {
  REPO="${REPOS[$1]}"
  echo "FROM $REGISTRY/$REPO"
}

update_exists() {
  REPO="${REPOS[$1]}"
#  LATEST="`wget -qO- http://$REGISTRY/v2/$REPO/tags/list`"
#  LATEST=`echo $LATEST | sed "s/{//g" | sed "s/}//g" | sed 's/.*tags"://' | sed "s/\"//g" | cut -d ' ' -f2`
#
#  RUNNING=`docker inspect "$REGISTRY/$REPO" | grep Id | sed "s/\"//g" | sed "s/,//g" |  tr -s ' ' | cut -d ' ' -f3`

  LATEST=$(curl --silent -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "http://$REGISTRY/v2/$REPO/manifests/latest" | jq -r '.config.digest')
  RUNNING=$(docker images -q --no-trunc $REPO:latest)

  if [ "$RUNNING" == "$LATEST" ];then
    return 1
  else
    return 0
  fi
}

REGISTRY="35.185.239.138:5000"
declare -A REPOS
REPOS['front']='front-suroo-kg'
REPOS['back']='back-suroo-kg'

# update local images before check
docker pull $REGISTRY/${REPOS['front']}
docker pull $REGISTRY/${REPOS['back']}

if update_exists 'front' ; then
  pull 'front'
else
  echo 'Front is latest version'
fi

sleep 1

if update_exists "back" ; then
  pull 'back'
else
  echo 'Back is latest version'
fi

