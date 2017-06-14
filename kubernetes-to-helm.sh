#!/bin/bash

set -eux

PROJECT=$1
WORKING_DIRECTORY="$GOPATH/src/github.com/giantswarm/$PROJECT"
KUBERNETES_DIRECTORY="kubernetes"
HELM_DIRECTORY="helm"
CHART_NAME="$PROJECT-chart"
CHART_FILE="Chart.yaml"
VALUES_FILE="values.yaml"
TEMPLATES_DIRECTORY="templates"

echo "Converting $PROJECT ($WORKING_DIRECTORY) from kubernetes/ to helm chart"

eval $( gpg-agent --daemon )

cd $WORKING_DIRECTORY

# Check the project state is okay - that a kubernetes directory exists,
# and we haven't already converted this project to helm.
if [ ! -d "$KUBERNETES_DIRECTORY" ]; then
    echo "kubernetes directory does not exist, aborting"
    exit 1
fi

if [ -d "$HELM_DIRECTORY" ]; then
    echo "helm directory exists already, aborting"
    exit 1
fi

if [ -d "$HELM_DIRECTORY/$CHART_NAME" ]; then
    echo "chart directory exists already, aborting"
    exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ $BRANCH != "master" ]; then
    echo "not on master branch, aborting"
    exit 1
fi

git pull

# Make the chart directory.
mkdir -p "./$HELM_DIRECTORY/$CHART_NAME"

# Create an empty values file.
touch "./$HELM_DIRECTORY/$CHART_NAME/$VALUES_FILE"

# Create a chart file.
cat > "./$HELM_DIRECTORY/$CHART_NAME/$CHART_FILE" <<EOL
name: $CHART_NAME
version: 1.0.0-{{ .SHA }}
EOL

# Copy over existing kubernetes resources.
cp -r "./$KUBERNETES_DIRECTORY" "./$HELM_DIRECTORY/$CHART_NAME/$TEMPLATES_DIRECTORY/" 

# Convert any .yml file extensions to .yaml.
# See https://stackoverflow.com/a/21985531/108452
find "./$HELM_DIRECTORY/$CHART_NAME/$TEMPLATES_DIRECTORY/" -name "*.yml" -exec bash -c 'mv "$1" "${1%.yml}".yaml' - '{}' \;

# Convert any instances of '%%DOCKER_TAG%%' to '{{ .Sha }}',
# this is a hold over from our original templating work.
find "./$HELM_DIRECTORY/$CHART_NAME/$TEMPLATES_DIRECTORY/" -type f -exec sed -i '' 's/%%DOCKER_TAG%%/{{ .Sha }}/g' {} +

# Convert any instances of '{{ .BuildInfo' to '{{ ',
# as architect templating now provides build info as top level variables.
# e.g: {{ .BuildInfo.Sha }} becomes {{ .Sha }}.
find "./$HELM_DIRECTORY/$CHART_NAME/$TEMPLATES_DIRECTORY/" -type f -exec sed -i '' 's/{{ .BuildInfo/{{ /g' {} +

# Convert any instances of '{{ .Installation' to '{{ .Values.Installation',
# as these values are now handled by helm during installation.
# e.g {{ .Installation.V1.GiantSwarm.API.Address.Host }} becomes {{ .Values.Installation.V1.GiantSwarm.API.Address.Host }}.
find "./$HELM_DIRECTORY/$CHART_NAME/$TEMPLATES_DIRECTORY/" -type f -exec sed -i '' 's/{{ .Installation/{{ .Values.Installation/g' {} +

# checkout new branch
git co -b add-helm-chart
git add "$HELM_DIRECTORY"
git commit -m "Adds helm chart"