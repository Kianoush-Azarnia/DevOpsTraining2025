Using `:latest` is considered bad practice for exactly that reason. Here's a comprehensive tagging strategy for GitLab CI/CD with stage and main environments:

The Problems with :latest:
Mutable: Can change unexpectedly

Unreliable: Someone might push a broken image

Untraceable: Hard to track what's actually deployed

Unsafe: No rollback certainty

Recommended Tagging Strategy:
1. Semantic Versioning + Git SHA + Environment
yaml
# Format: {major}.{minor}.{patch}-{env}-{git_sha_short}
# Examples:
1.2.3-staging-a1b2c3d
1.2.3-production-e5f6g7h
2.0.0-staging-x8y9z0a
2. GitLab CI/CD Implementation:
yaml
# .gitlab-ci.yml
variables:
  # Registry settings
  REGISTRY_URL: "registry.mycompany.com"
  PROJECT_PATH: "mygroup/myproject"
  
  # Derived variables
  APP_VERSION: "1.0.0"  # Could also auto-increment
  GIT_SHA_SHORT: "$CI_COMMIT_SHORT_SHA"
  ENVIRONMENT: "$CI_COMMIT_REF_NAME"  # or manual setting

stages:
  - build
  - test
  - deploy-staging
  - deploy-production

build:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    # Build with multiple tags
    - |
      docker build \
        -t $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-staging-$GIT_SHA_SHORT \
        -t $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-staging-latest \
        -t $REGISTRY_URL/$PROJECT_PATH:staging-$GIT_SHA_SHORT \
        .
    
    # Push all tags
    - docker push $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-staging-$GIT_SHA_SHORT
    - docker push $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-staging-latest
    - docker push $REGISTRY_URL/$PROJECT_PATH:staging-$GIT_SHA_SHORT
  only:
    - develop  # Staging builds from develop branch

build-production:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    # Production builds get version tags only (no "latest")
    - |
      docker build \
        -t $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-production-$GIT_SHA_SHORT \
        -t $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION \
        .
    
    - docker push $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-production-$GIT_SHA_SHORT
    - docker push $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION
  only:
    - main  # Production builds from main branch

deploy-staging:
  stage: deploy-staging
  script:
    # Deploy the specific SHA-tagged image
    - |
      kubectl set image deployment/myapp \
        myapp=$REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-staging-$GIT_SHA_SHORT
  environment:
    name: staging
  only:
    - develop

deploy-production:
  stage: deploy-production
  script:
    # Deploy the version-tagged image (no "latest")
    - |
      kubectl set image deployment/myapp \
        myapp=$REGISTRY_URL/$PROJECT_PATH:$APP_VERSION
  environment:
    name: production
  only:
    - main
  when: manual  # Require manual approval for production
3. Advanced GitLab CI with Auto-Versioning:
yaml
# .gitlab-ci.yml with automatic versioning
variables:
  REGISTRY_URL: "registry.mycompany.com"
  PROJECT_PATH: "mygroup/myproject"

stages:
  - version
  - build
  - deploy

determine-version:
  stage: version
  script:
    # Auto-determine version based on commit message or branch
    - |
      if [[ "$CI_COMMIT_REF_NAME" == "main" ]]; then
        # Use package.json version or generate from git tags
        export APP_VERSION=$(node -p "require('./package.json').version")
        echo "APP_VERSION=$APP_VERSION" > version.env
      else
        # For staging, use branch name + timestamp
        export APP_VERSION="0.0.0-${CI_COMMIT_REF_NAME}-$(date +%Y%m%d%H%M)"
        echo "APP_VERSION=$APP_VERSION" > version.env
      fi
    - echo "VERSION=$APP_VERSION"
  artifacts:
    reports:
      dotenv: version.env

build-image:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    - |
      docker build \
        -t $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION \
        -t $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-$CI_COMMIT_SHORT_SHA \
        .
    - docker push $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION
    - docker push $REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-$CI_COMMIT_SHORT_SHA
  dependencies:
    - determine-version

deploy-staging:
  stage: deploy
  script:
    - |
      kubectl set image deployment/myapp-staging \
        myapp=$REGISTRY_URL/$PROJECT_PATH:$APP_VERSION-$CI_COMMIT_SHORT_SHA
  environment:
    name: staging
    url: https://staging.myapp.com
  only:
    - develop
    - feature/*
  except:
    - main

deploy-production:
  stage: deploy
  script:
    - |
      kubectl set image deployment/myapp-production \
        myapp=$REGISTRY_URL/$PROJECT_PATH:$APP_VERSION
  environment:
    name: production
    url: https://myapp.com
  only:
    - main
  when: manual
4. Dockerfile Best Practices:
dockerfile
# Use specific base image, not latest
FROM node:18.18.0-alpine@sha256:abc123def456...

# Add build metadata labels
LABEL org.opencontainers.image.version="$APP_VERSION"
LABEL org.opencontainers.image.revision="$CI_COMMIT_SHA"
LABEL org.opencontainers.image.created="$BUILD_DATE"

# Build arguments for traceability
ARG APP_VERSION
ARG GIT_SHA
ARG BUILD_DATE

# Environment variables for runtime identification
ENV APP_VERSION=$APP_VERSION
ENV GIT_SHA=$GIT_SHA
ENV BUILD_DATE=$BUILD_DATE

# ... rest of Dockerfile
5. Kubernetes Deployment Examples:
Staging Deployment (Specific SHA)
yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-staging
  labels:
    app: myapp
    environment: staging
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        environment: staging
        version: "1.2.3-staging-a1b2c3d"
    spec:
      containers:
      - name: myapp
        image: registry.mycompany.com/mygroup/myproject:1.2.3-staging-a1b2c3d
        env:
        - name: APP_ENV
          value: "staging"
        - name: APP_VERSION
          value: "1.2.3-staging-a1b2c3d"
Production Deployment (Version Only)
yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-production
  labels:
    app: myapp
    environment: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        environment: production
        version: "1.2.3"
    spec:
      containers:
      - name: myapp
        image: registry.mycompany.com/mygroup/myproject:1.2.3
        env:
        - name: APP_ENV
          value: "production"
        - name: APP_VERSION
          value: "1.2.3"
6. Tagging Strategy Summary:
Environment	Tag Format	Purpose
Staging	1.2.3-staging-a1b2c3d	Specific, traceable deployments
Staging	staging-a1b2c3d	Easy manual deployment
Production	1.2.3	Semantic version for releases
Production	1.2.3-production-a1b2c3d	Audit trail
Both	1.2.3-a1b2c3d	Git SHA reference
7. Additional Safe "Latest" Alternatives:
If you really need a "latest-like" behavior:

yaml
# Only for staging, and only automated
build-staging:
  script:
    - docker build -t $REGISTRY_URL/$PROJECT_PATH:staging-latest .
    - docker push $REGISTRY_URL/$PROJECT_PATH:staging-latest
  only:
    - develop

# But still deploy with specific tags!
deploy-staging:
  script:
    # NEVER deploy "staging-latest" in automation
    - kubectl set image deployment/myapp myapp=$REGISTRY_URL/$PROJECT_PATH:1.2.3-staging-a1b2c3d
8. Benefits of This Strategy:
Traceability: Every deployment can be traced to exact git commit

Rollbacks: Easy to rollback to previous known-good versions

Auditing: Clear audit trail of what was deployed when

Safety: No accidental deployments of untested images

Clarity: Clear distinction between staging and production images

Key Principle:
Never deploy mutable tags in production. Always use immutable, versioned tags that clearly identify the exact build and commit.

This approach gives you the safety and traceability of immutable deployments while still providing the convenience of clear versioning for your staging and production environments.

# Question
  > How to know which version is getting chosen as the `latest`?

There are several ways to figure out which specific version/digest is being chosen as "latest". Here are the main approaches:

1. Pull and Inspect (Most Direct)
bash
# Pull the image
docker pull myDockerRegistry.com/myCompany/app:latest

# Inspect to see the actual digest
docker inspect myDockerRegistry.com/myCompany/app:latest | grep Digest

# Or use docker images with --digests flag
docker images --digests myDockerRegistry.com/myCompany/app
2. Use Registry API (Most Accurate)
bash
# Get the manifest which shows the actual digest for 'latest'
curl -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  https://myDockerRegistry.com/v2/myCompany/app/manifests/latest \
  -I | grep -i "docker-content-digest"

# Or get full manifest details
curl -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  https://myDockerRegistry.com/v2/myCompany/app/manifests/latest
3. Pull with Detailed Output
bash
# Pull with detailed output that shows the digest
docker pull myDockerRegistry.com/myCompany/app:latest

# Look for lines like:
# latest: Pulling from mycompany/app
# Digest: sha256:abc123def456...
# Status: Downloaded newer image for myDockerRegistry.com/myCompany/app:latest@sha256:abc123def456...
4. Check Local Image Digest
bash
# If you've already pulled the image
docker images --digests | grep "myDockerRegistry.com/myCompany/app"

# Or get specific details
docker image inspect myDockerRegistry.com/myCompany/app:latest --format '{{.RepoDigests}}'
5. Registry-Specific Methods
Docker Hub
bash
# For Docker Hub (if it's a public image)
curl -s "https://hub.docker.com/v2/repositories/myCompany/app/tags/latest" | jq .

# Or use skopeo tool
skopeo inspect docker://myDockerRegistry.com/myCompany/app:latest
Amazon ECR
bash
# For AWS ECR
aws ecr describe-images \
  --repository-name myCompany/app \
  --image-ids imageTag=latest

# Or get the specific image manifest
aws ecr batch-get-image \
  --repository-name myCompany/app \
  --image-ids imageTag=latest
Google Container Registry (GCR)
bash
# For GCR
gcloud container images describe gcr.io/myCompany/app:latest

# Or using crane tool
crane manifest gcr.io/myCompany/app:latest
Azure Container Registry (ACR)
bash
# For ACR
az acr repository show-manifests \
  --name myRegistry \
  --repository myCompany/app \
  --detail
6. Using Docker Manifest (Modern Approach)
bash
# Enable experimental features first (if needed)
export DOCKER_CLI_EXPERIMENTAL=enabled

# Inspect the manifest
docker manifest inspect myDockerRegistry.com/myCompany/app:latest

# This will show the exact digest and platform-specific manifests
7. Using Third-Party Tools
Skopeo (Recommended)
bash
# Install skopeo first
skopeo inspect docker://myDockerRegistry.com/myCompany/app:latest

# This shows the exact digest, created date, and other metadata
Dive
bash
# Pull and analyze
docker pull myDockerRegistry.com/myCompany/app:latest
dive myDockerRegistry.com/myCompany/app:latest
Practical Example Workflow:
bash
# Method 1: Quick check after pull
docker pull myDockerRegistry.com/myCompany/app:latest
docker images --digests | grep "myDockerRegistry.com/myCompany/app"

# Output example:
# myDockerRegistry.com/myCompany/app   latest   sha256:abc123...   2 hours ago   1.2GB

# Method 2: Registry API (without pulling)
curl -s -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  https://myDockerRegistry.com/v2/myCompany/app/manifests/latest \
  | jq -r '.config.digest'

# Output: sha256:def456...
Understanding the Output:
When you get a digest like sha256:abc123def456..., this is the cryptographic hash of the image contents. This is what actually identifies the specific version, not the "latest" tag.

To See What "Latest" Points To Over Time:
bash
# Create a script to track changes
#!/bin/bash
REGISTRY="myDockerRegistry.com"
REPO="myCompany/app"

while true; do
    DIGEST=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "https://${REGISTRY}/v2/${REPO}/manifests/latest" -I \
        | grep -i "docker-content-digest" | cut -d' ' -f2 | tr -d '\r')
    echo "$(date): latest -> $DIGEST"
    sleep 3600  # Check every hour
done
One-Liner for Quick Check:
bash
# Single command to see what 'latest' resolves to
docker pull myDockerRegistry.com/myCompany/app:latest > /dev/null 2>&1 && \
  docker inspect myDockerRegistry.com/myCompany/app:latest --format '{{index .RepoDigests 0}}'
Security Consideration:
Always verify the digest when using "latest" in production, as the same tag can point to different content over time:

bash
# Instead of relying on 'latest', use specific digests in production
docker pull myDockerRegistry.com/myCompany/app@sha256:abc123def456...
The digest (sha256 hash) is the only truly immutable reference to a specific image version, while tags like "latest" are mutable pointers that can change.