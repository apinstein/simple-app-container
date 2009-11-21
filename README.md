Simple Application Container
-------------------------

An architecture for bootstrapping, sandboxing, and deploying applications.

This project consists of the **organizational architecture**, and the **capistrano implementation**.

A project organized with this architecture is sandboxed in its own unix security cocoon yet can still restart itself (ie hup apache), manage its own services (via runit), and monitor its health (via monit).

Tasks to bootstrap an "application" user container:

ACCOUNT & PERMISSIONS

- add user "app"; install ssh key
- add group "app-web"
  (means both app and httpd user can access files)

RUNIT

- create ~app/service directory (app can symlink services there as needed)
- create ~root/app-runsvdir && install service code (run & finish), w/chpst to app/app-web
- symlink ~root/app-runsvdir to /service

![runit service architecture](http://github.com/apinstein/php-app-container/raw/master/rendered/runit-architecture.png)

SUDO

- give sudo apachectl restart privs to app

ANYTHING ELSE?

Applications can now manage themselves:

- Install services via "ln -s /path/to/service ~/app/service
- Restart apache via "sudo apachectl restart"
- Managing cron deployments via "crontab /path/to/crontab"

