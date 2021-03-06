#!/usr/bin/bash
set -eux

# Simple CI test to sanity test commits

# Make sure docker is running
sudo systemctl start docker

# Display the current commit
git log -1

# Run unit tests
tox -epy27

# Run pep8 tests
tox -epep8

# Create build images, this will endup being a noop on hosts where
# it was already run if the dockerfile hasn't changed
./scripts/create_build_image.sh fedora
./scripts/create_build_image.sh centos

# Use the env setup by tox
set +u
. .tox/py27/bin/activate
set -u

# Build this if not building a specific project
PROJECT_TO_BUILD=python-glanceclient
PROJECT_TO_BUILD_MAPPED=$(./scripts/map-project-name $PROJECT_TO_BUILD)

# If this is a CI run for one of the distro repositories then we pre download it
# into the data directory, delorean wont change it because we are using --dev
if [ -n "$GERRIT_PROJECT" ] && [ "$GERRIT_PROJECT" != "openstack-packages/delorean" ] ; then
    mkdir -p data/repos
    PROJECT_TO_BUILD=${GERRIT_PROJECT#*/}
    PROJECT_TO_BUILD_MAPPED=$(./scripts/map-project-name $PROJECT_TO_BUILD)
    PROJECT_DISTRO_DIR=${PROJECT_TO_BUILD_MAPPED}_distro
    git clone https://review.gerrithub.io/"$GERRIT_PROJECT" data/$PROJECT_DISTRO_DIR
    pushd data/$PROJECT_DISTRO_DIR
    git fetch https://review.gerrithub.io/$GERRIT_PROJECT $GERRIT_REFSPEC && git checkout FETCH_HEAD
    popd
fi

function copy_logs(){
    cp -r data/repos logs/$DISTRO
}

# If the command below throws an error we still want the logs
trap copy_logs ERR

# And Run delorean against a project
DISTRO=fedora
delorean --config-file projects.ini --head-only --package-name $PROJECT_TO_BUILD_MAPPED --dev

# Copy files to be archived
copy_logs

# Switch to a centos target
sed -i -e 's%target=.*%target=centos%' projects.ini
sed -i -e 's%baseurl=.*%baseurl=http://trunk.rdoproject.org/centos70%' projects.ini

# And run delorean again
DISTRO=centos
delorean --config-file projects.ini --head-only --package-name $PROJECT_TO_BUILD_MAPPED --dev

# Copy files to be archived
copy_logs
