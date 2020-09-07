# CentOS 8 systemd-nspawn containers

## Introduction
From the manual

Spawn a command or OS in a light-weight container

systemd-nspawn may be used to run a command or OS in a light-weight namespace container. In many ways it is similar to chroot(1), but more powerful since it fully virtualizes the file system hierarchy, as well as the process tree, the various IPC subsystems and the host and domain name.

## Steps
Set SELinux to permissive before beginning

`setenforce 0`

`dnf install systemd-container`

`mkdir /var/lib/machines/cent8 -p`

`dnf -y --nogpgcheck --releasever=8 --installroot /var/lib/machines/cent8 install systemd vim-minimal bash-completion openssl gpg initscripts sudo cronie python38 tar hostname which passwd setup yum dnf iproute`

Boot the container and change password of root user

`systemd-nspawn -D /var/lib/machines/cent8`

`passwd`

`logout`

Now you can boot the container and login

`systemd-nspawn -bD /var/lib/machines/cent8`

Enable Auto-start at boot

`systemctl enable machines.target`

`machinectl enable cent8`

Start and login

`machinectl start cent8`

`machinectl login cent8`

## To use host machine's network
By default only loopback interface is available in the container

Remove `--network-veth` parameter from /etc/systemd/system/machines.target.wants/systemd-nspawn@cent8.service

`systemctl daemon-reload`

`machinectl poweroff cent8`

`machinectl start cent8`

## SELinux
`restorecon -R /var/lib/machines/cent8/`

`setsebool -P domain_can_mmap_files 1`

`setsebool -P daemons_use_tty 1`

``` 
#============= setroubleshootd_t ==============
allow setroubleshootd_t var_lib_t:file { lock open read };

#============= system_dbusd_t ==============
allow system_dbusd_t devpts_t:chr_file { read write };

#============= systemd_machined_t ==============
allow systemd_machined_t self:cap_userns { kill setgid setuid sys_admin sys_ptrace };
allow systemd_machined_t systemd_unit_file_t:service stop;
allow systemd_machined_t tmpfs_t:lnk_file read;
allow systemd_machined_t tmpfs_t:sock_file write;
allow systemd_machined_t unconfined_service_t:dir search;
allow systemd_machined_t unconfined_service_t:file { getattr open read };
allow systemd_machined_t unconfined_service_t:lnk_file read; 

```
