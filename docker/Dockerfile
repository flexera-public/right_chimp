# Runs right_chimp (https://rubygems.org/gems/right_chimp) ruby gem from a container
###
# Arbitrary chimp commands executed in container -or- defaults to running execution daemon ('chimpd')
# * Requires volume share with creds to /root/
# - ex1 - Execute arbitrary chimp command:
# => docker run -it -p -v ~/.rest_connection:/root/.rest_connection:ro mastamark/right_chimp:latest chimp --tag="some:tag=true" --script="MyScript"
# - ex2 - Start right_chimp daemon with docker host port 9055 bound to same container port:
# => docker run -d -p 9055:9055 -v ~/.rest_connection:/root/.rest_connection:ro mastamark/right_chimp:latest
# Send your dockerized chimp queries to your dockerized chimpd by adding flag "--chimpd=172.17.0.1:9055" (assuming this is your docker host ip) to chimp queries.
###
# Built via: docker build -t mastamark/right_chimp:latest .
###

FROM rightscale/ops_ruby23x_build
MAINTAINER mastamark+github@gmail.com
WORKDIR /srv
ADD right_chimp.sh /srv/

RUN gem install right_chimp --no-ri --no-rdoc

ENTRYPOINT ["/srv/right_chimp.sh"]
CMD ["chimpd"]
EXPOSE 9055
