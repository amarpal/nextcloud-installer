#install-nextcloud todo

- [ ] add trusted domain to config.php
- [ ] configure redis for nextcloud 16
- [ ] write a script to install DDclient and schedule updates w/ddclient.conf
- [ ] update install script with nextcloud 15 prerequisites
- [ ] write an uninstall script

```bash
#ddclient.conf

#tell ddclient how to get your ip address
use=web, web=ip.changeip.com

#provide server and login details
protocol=changeip
ssl=yes
server=nic.changeip.com/nic/update
login=$email
password=$pass

#specify the domain to update
host.dynamic-dns.net
```
