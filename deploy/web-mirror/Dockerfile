# The web mirror. github.io is blocked in Yemen, while Northflank's code.run
# (the API's host) is reachable there, so a second free Northflank service
# serves the very build GitHub Pages serves.
#
# Built from the `web-dist` branch, never from main: the Deploy Web workflow
# force-pushes one commit there holding this Dockerfile, nginx.conf and the
# build under site/nukhbaa/. The build is not repeated here, so the service
# builds in seconds and never runs dart2js on Northflank.
FROM nginxinc/nginx-unprivileged:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/
EXPOSE 8080
