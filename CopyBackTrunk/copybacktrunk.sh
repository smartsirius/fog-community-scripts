#!/bin/bash
path=$1
[[ -z $path || ! -e "$HOME/$path" ]] && path="$HOME/fogproject"
rsync -a --no-links -heP --delete $path/packages/web/ /var/www/fog/
cp ~/config.class.php /var/www/fog/lib/fog/config.class.php
chown -R apache:apache /var/www/fog
chown -R fogproject:apache /var/www/fog/service/ipxe
