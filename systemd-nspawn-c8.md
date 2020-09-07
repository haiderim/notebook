# CentOS 8 systemd-nspawn containers

## Introduction
From the manual

Spawn a command or OS in a light-weight container

systemd-nspawn may be used to run a command or OS in a light-weight namespace container. In many ways it is similar to chroot(1), but more powerful since it fully virtualizes the file system hierarchy, as well as the process tree, the various IPC subsystems and the host and domain name.

## Steps
Set SELinux to permissive before beginning

`setenforce 0`

`yum -y --nogpgcheck --releasever=8 --installroot /var/lib/machines/cent8 install systemd vim-minimal bash-completion openssl gpg net-tools initscripts bind-utils sudo cronie python tar hostname which passwd setup yum dnf`

Boot the container and change password of root user

`systemd-nspawn -D /var/lib/machines/cent8`

`passwd`

`logout`

Now you can boot the container and login

`systemd-nspawn -bD /var/lib/machines/cent8`

Auto-start at boot

`machinectl enable cent8`

`rm /var/lib/machines/cent7/etc/securetty`

`machinectl start cent8`
