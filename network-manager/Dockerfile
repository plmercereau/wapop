# 22.04 to use the same nm version as the host...
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    network-manager \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

