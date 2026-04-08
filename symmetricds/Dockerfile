#FROM openjdk:17-jdk-slim
FROM eclipse-temurin:17-jdk

WORKDIR /opt

COPY symmetric-server-3.16.4.zip .

RUN apt-get update && apt-get install -y unzip && \
    unzip symmetric-server-3.16.4.zip && \
    mv symmetric-server-3.16.4 symmetricds && \
    rm symmetric-server-3.16.4.zip && \
    apt-get remove -y unzip && apt-get autoremove -y && \
    chmod +x /opt/symmetricds/bin/*

WORKDIR /opt/symmetricds
