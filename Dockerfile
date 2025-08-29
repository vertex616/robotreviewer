FROM node:12-alpine as build-stage

WORKDIR /app
RUN npm update
RUN npm install -g requirejs
COPY ./robotreviewer/static/ static/

# compile client side assets
RUN r.js -o static/build.js && \
    mv static static.bak && \
    mv build static && \
    rm -rf static.bak

FROM ubuntu:18.04 as production-stage

ENV DEBIAN_FRONTEND=noninteractive

# create deploy user
RUN useradd --create-home --home /var/lib/deploy deploy

# install apt-get requirements
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    aria2 \
    software-properties-common \
    curl \
    openssl \
    ca-certificates \
    libxml2 \
    wget \
    libsm6 \
    libxrender1 \
    libfontconfig1 \
    git \
    sudo \
    cron && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Certs
RUN mkdir -p /etc/pki/tls/certs && \
    ln -s /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt

RUN chown -R deploy.deploy /var/lib/deploy/

USER deploy

# install Anaconda
RUN aria2c -s 16 -x 16 -k 30M https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /var/lib/deploy/Anaconda.sh
RUN cd /var/lib/deploy && bash Anaconda.sh -b && rm -rf Anaconda.sh
ENV PATH=/var/lib/deploy/miniconda3/bin:$PATH

ADD robotreviewer_env.yml tmp/robotreviewer_env.yml
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
RUN conda env create -f tmp/robotreviewer_env.yml

# Activate conda environment
ENV PATH=/var/lib/deploy/miniconda3/envs/robotreviewer/bin:$PATH

RUN python -m nltk.downloader punkt stopwords
RUN python -m spacy download en

ARG TFVER=tensorflow
RUN pip install $TFVER==1.12.0

# Get data
USER root

RUN mkdir -p /var/lib/deploy/robotreviewer/data
ADD server.py /var/lib/deploy/
ADD server_api.py /var/lib/deploy/
ADD entrypoint.sh /var/lib/deploy/
ADD clean_uploaded_pdfs.py /var/lib/deploy/
ADD crontab /etc/cron.d/crontab
ADD robotreviewer /var/lib/deploy/robotreviewer
RUN chown -R deploy.deploy /var/lib/deploy/robotreviewer

USER deploy

COPY --from=build-stage /app/static /var/lib/deploy/robotreviewer/static

ENV HOME=/var/lib/deploy

USER root

RUN pip install gunicorn gevent

# Copy entrypoint.sh into the image
COPY entrypoint.sh /var/lib/deploy/entrypoint.sh

# Make it executable
RUN chmod +x /var/lib/deploy/entrypoint.sh

ENTRYPOINT ["/var/lib/deploy/entrypoint.sh"]