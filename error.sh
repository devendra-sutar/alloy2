Get:1 https://apt.grafana.com stable InRelease [7661 B]
Err:1 https://apt.grafana.com stable InRelease                                                             
  The following signatures couldn't be verified because the public key is not available: NO_PUBKEY 963FA27710458545
Get:2 http://security.ubuntu.com/ubuntu noble-security InRelease [126 kB]                                  
Get:3 http://intel-az1.clouds.archive.ubuntu.com/ubuntu noble InRelease [256 kB]       
Get:4 http://security.ubuntu.com/ubuntu noble-security/main amd64 Components [7188 B]  
Get:5 http://security.ubuntu.com/ubuntu noble-security/universe amd64 Components [51.9 kB]
Get:6 http://security.ubuntu.com/ubuntu noble-security/restricted amd64 Components [212 B]
Get:7 http://security.ubuntu.com/ubuntu noble-security/multiverse amd64 Components [212 B]
Get:8 http://intel-az1.clouds.archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]
Hit:9 http://intel-az1.clouds.archive.ubuntu.com/ubuntu noble-backports InRelease
Reading package lists... Done
W: GPG error: https://apt.grafana.com stable InRelease: The following signatures couldn't be verified because the public key is not available: NO_PUBKEY 963FA27710458545
E: The repository 'https://apt.grafana.com stable InRelease' is not signed.
N: Updating from such a repository can't be done securely, and is therefore disabled by default.
N: See apt-secure(8) manpage for repository creation and user configuration details.
Installing gnupg...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
gnupg is already the newest version (2.4.4-2ubuntu17).
0 upgraded, 0 newly installed, 0 to remove and 106 not upgraded.
Creating APT keyring directory...
Adding Grafana GPG key...
Adding Grafana repository...
Installing Alloy...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
E: Unable to locate package alloy
Creating Alloy directory...
Backing up config.alloy...
Installing acl...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
acl is already the newest version (2.3.2-1build1.1).
0 upgraded, 0 newly installed, 0 to remove and 106 not upgraded.
Setting ACL for alloy user on /var/log...
usermod: homedir must be an absolute path
setfacl: Option -m: Invalid argument near character 3
setfacl: Option -m: Invalid argument near character 3
Copying the Alloy config file...
Enabling and restarting Alloy service...
Failed to enable unit: Unit file alloy.service does not exist.
Failed to restart alloy.service: Unit alloy.service not found.
Checking Alloy service status...
Unit alloy.service could not be found.
Sending POST request to create new agent...
{"message": "Agent created successfully"}POST request sent successfully.
