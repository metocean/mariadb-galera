FROM ubuntu:14.04
ENV DEBIAN_FRONTEND noninteractive

ADD mariadb.list /etc/apt/sources.list.d/
RUN chown root: /etc/apt/sources.list.d/mariadb.list
RUN apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db && \
    apt-get update && \
    apt-get install -y mariadb-galera-server galera dnsutils wget unzip curl jq

ENV CONSUL_VERSION=1.12.2
RUN echo "-----------------Install Consul-----------------" &&\
    cd /tmp &&\
    mkdir /consul &&\
    wget -q https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip &&\
    unzip consul_${CONSUL_VERSION}_linux_amd64.zip &&\
    mv consul /usr/bin &&\
    rm -r consul_${CONSUL_VERSION}_linux_amd64.zip 

COPY my.cnf /etc/mysql/my.cnf
COPY mysqld.sh /mysqld.sh

RUN chmod 555 /mysqld.sh

# Define mountable directories.
VOLUME ["/var/lib/mysql"]

# Define default command.
ENTRYPOINT ["/mysqld.sh"]
