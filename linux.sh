#!/usr/bin/env bash

#In order to ensure the script is ran under root privileges 
if [ $(whoami) != 'root' ]; then
        echo 'Please run this script with root privileges (sudo preferred)'
        exit 1;

fi

#In order to set the webpage URL, I am editing the /etc/hosts tab to reflect the name associated with the certificate. 
echo "localhost webpage.com webpage" >> /etc/hosts

#First step is to install Apache
dnf install httpd -y

#Then enable and start Apache
systemctl enable httpd
systemctl start httpd

#Then the mod_ssl needs to be installed to enable SSL encryption
dnf install mod_ssl

#Restarting Apache to ensure changes are applied
systemctl restart httpd

#Creating webpage as requested: 
echo "My awesome webpage!" > /var/www/html/devsecops_practical

# Enabling the firewall to support http and https 
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

#Creating the x.509 key pair
#It wasn't in the man pages, but the -subj flag removes the prompts with prefilled data 
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/pki/tls/private/apache-selfsigned.key -out /etc/pki/tls/certs/apache-selfsigned.crt -subj "/C=US/ST=Colorado/L=Denver/O=NorthropGrumman/OU=IT/CN=webpage.com"

#Modifying the permission/ownership of the keys for the ApacheUser 
chown apacheuser:apacheuser /etc/pki/tls/private/apache-selfsigned.key
chmod 700 /etc/pki/tls/private/apache-selfsigned.key
chown apacheuser:apacheuser /etc/pki/tls/certs/apache-selfsigned.crt
chmod 700 /etc/pki/tls/certs/apache-selfsigned.crt

#Creating a file to utilize the key with the webpage.
 echo -e "<VirtualHost *:443>\nServerName webpage.com\nDocumentRoot /var/www/html\nSSLEngine on\nSSLCertificateFile /etc/pki/tls/certs/apache-selfsigned.crt\nSSLCertificateKeyFile /etc/pki/tls/private/apache-selfsigned.key\n</VirtualHost>\n \n<VirtualHost *:80>\nServerName webpage.com\nRedirect / https://webpage/\n</VirtualHost>" > /etc/httpd/conf.d/webpage.conf

#V-214245: The Apache web server must have WebDAV disabled
#Note: Since this script is responsible for the installation, I assumed the location of the module. If this was meant to be a portable solution, I would have incorporated a search to identify it. 
sed -i '1,3 s/^/#/' /etc/httpd/conf.modules.d/00-dav.conf

#V-214246: The Apache web server must be configured to use a specified IP address and port 
sed -i '/#Listen 12.34.56.78:80/ c\Listen 172.16.120.145:80' /etc/httpd/conf/httpd.conf

#V-214228: The Apache web server must limit the number of allowed simultaneous session requests 
        #The below if statement is meant to check if KeepAlive is toggled off, in which the sed command will toggle it on. If it doesn't exist however, the else if will append it to the bottom of the conf file. 
if [[ $(grep -i ^KeepAlive /etc/httpd/conf/httpd.conf) = 'KeepAlive off' ]]; then sed -i '/KeepAlive off/ c\KeepAlive on' /etc/httpd/conf/httpd.conf; elif [ -z $(grep -i ^KeepAlive /etc/httpd/conf/httpd.conf) ]; then echo "KeepAlive on" >> /etc/httpd/conf/httpd.conf; fi

        # The below function is meant to identify if the MaxKeepAliveRequests are below 100, if so, it replaces the number with 100. If it does not exist at all, it is appended to the conf file. 
if [[ $(grep -i MaxKeepAliveRequests /etc/httpd/conf/httpd.conf | sed s/[^0-9]*//g) -le 99 ]]; then sed -i '/MaxKeepAliveRequests/ c\MaxKeepAliveRequests 100' /etc/httpd/conf/httpd.conf; elif [[ -z $(grep -i MaxKeepAliveRequests /etc/httpd/conf/httpd.conf) ]]; then echo "MaxKeepAliveRequests 100" >> /etc/httpd/conf/httpd.conf; fi

#V-214271: The account used to run the Apache web server must not have a valid login shell and password defined
#This command ensures the user apache has login shell /sbin/nologin
if [[ $(cut -d: -f1,7 /etc/passwd | grep -i apache:) != 'apache:/sbin/nologin' ]]; then usermod apache -s /sbin/nologin; fi

#This will ensure the password is locked as well
if [[ $(cut -d: -f1,2 /etc/shadow | grep -i apache:) != 'apache:!!' ]]; then passwd -l apache; fi

#V-214255: The Apache web server must be tuned to handle the operational requirements  of the hosted application
if [[ -z $(grep -i ^Timeout /etc/httpd/conf/httpd.conf) ]]; then echo "Timeout 10" >> /etc/httpd/conf/httpd.conf; fi
