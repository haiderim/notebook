# CentOS 8 systemd-nspawn containers

## Introduction
Spawn a command or OS in a light-weight container

systemd-nspawn may be used to run a command or OS in a light-weight namespace container. In many ways it is similar to chroot(1), but more powerful since it fully virtualizes the file system hierarchy, as well as the process tree, the various IPC subsystems and the host and domain name.

## Steps
Set SELinux to permissive before beginning

`setenforce 0`

On Minimal install, the systemd-nspawn command is unavailable

`dnf install systemd-container`

Create directory where you'll install the container

`mkdir /var/lib/machines/cent8 -p`

Install the container

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

## Use host machine's network
By default only loopback interface is available in the container, please refer the manual for more options

Remove `--network-veth` parameter from **/etc/systemd/system/machines.target.wants/systemd-nspawn@cent8.service**

`systemctl daemon-reload`

`machinectl poweroff cent8`

`machinectl start cent8`

## SELinux
`restorecon -R /var/lib/machines/cent8/`

`setsebool -P domain_can_mmap_files 1`

`setsebool -P daemons_use_tty 1`

Create SELinux module

`audit2allow -a -M systemd-nspawn`

`semodule -i systemd-nspawn.pp`

Output of `grep denied /var/log/audit/audit.log | audit2allow`  

```
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
You can now set SELinux back to enforcing

`setenforce 1`
