#***********************************************************
# This file is part of the Slock.it IoT Layer.             *
# The Slock.it IoT Layer contains:                         *
#   - USN (Universal Sharing Network)                      *
#   - INCUBED (Trustless INcentivized remote Node Network) *
#***********************************************************
# Copyright (C) 2016 - 2018 Slock.it GmbH                  *
# All Rights Reserved.                                     *
#***********************************************************
# You may use, distribute and modify this code under the   *
# terms of the license contract you have concluded with    *
# Slock.it GmbH.                                           *
# For information about liability, maintenance etc. also   *
# refer to the contract concluded with Slock.it GmbH.      *
#***********************************************************
# For more information, please refer to https://slock.it   *
# For questions, please contact info@slock.it              *
#**********************************************************/


FROM node:8

WORKDIR /app

ARG NPM_REGISTRY_TOKEN

COPY tsconfig.json  ./
COPY src  ./src/
COPY contracts  ./contracts/
COPY package.json ./

# allowing docker to access the private repo
RUN echo "//npm.slock.it/:_authToken=\"$NPM_REGISTRY_TOKEN\"" > ~/.npmrc \
    && npm set registry https://npm.slock.it \
    && npm install \
    && rm ~/.npmrc

# compile src
RUN npm run build

# clean up
# pruning does not work with git-modules, so we can use it when the repo is public
RUN npm prune --production 
RUN rm -rf src tsconfig.json ~/.npmrc

# setup ENTRYPOINT
EXPOSE 8500
ENTRYPOINT ["node", "js/server/server.js"]




