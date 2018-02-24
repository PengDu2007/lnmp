#!/bin/bash
# LNMP安装脚本, 适用系统版本CentOS7.*
# php7 + nginx1.12.2 + php7.1.13
# @author peng
# @version 2018/01/25 14:52:23 

# 设置目录
dir=/data
if [ ! -d $dir ]; then
	echo "Please create /web directory"
	exit 1
fi
currentDir=`pwd`
shellDir=$dir/shell
softDir=$dir/soft
logDir=$dir/log
backupDir=$dir/backup
cronDir=$dir/cron
wwwDir=$dir/www

# 创建文件夹
mkdir -p $shellDir/tools
mkdir -p $softDir
mkdir -p $logDir/nginx $logDir/php
mkdir -p $backupDir/log/nginx $backupDir/log/php $backupDir/code 
mkdir -p $cronDir
mkdir -p $wwwDir
mkdir -p /var/log/nginx /var/log/php

systemctl enable firewalld.service

# 添加用户以及组
# userdel www
groupadd www
useradd -g www -M -d $dir/www -s /sbin/nologin www &> /dev/null

# 更新源
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
yum clean all && yum makecache && yum -y update

# 安装支持库以及工具
yum -y install wget gcc gcc-c++ subversion

cd $shellDir/tools

yum -y install pcre pcre-devel openssl openssl-devel

# 安装nginx
if [ ! -f nginx-1.12.2.tar.gz ]; then
	wget http://nginx.org/download/nginx-1.12.2.tar.gz -O nginx-1.12.2.tar.gz
fi
tar -xzvf nginx-1.12.2.tar.gz

cd nginx-1.12.2
./configure --prefix=$softDir/nginx \
--user=www \
--group=www \
--error-log-path=$logDir/nginx/error.log \
--http-log-path=$logDir/nginx/access.log \
--with-http_ssl_module \
--with-http_realip_module \
--with-http_sub_module \
--with-http_dav_module \
--with-http_flv_module \
--with-http_gzip_static_module \
--with-http_stub_status_module \
--with-http_v2_module

make && make install

# 配置nginx站点
if [ -f $currentDir/nginx/nginx.conf ]; then
	cp  $currentDir/nginx/nginx.conf $softDir/nginx/conf/nginx.conf
fi
if [ -d $currentDir/nginx/vhosts ]; then
	cp -R $currentDir/nginx/vhosts $softDir/nginx/conf
fi
# 配置nginx服务
cat > /usr/lib/systemd/system/nginx.service <<EOF
[Unit]
Description=nginx
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
ExecStart=$softDir/nginx/sbin/nginx -c $softDir/nginx/conf/nginx.conf
ExecReload=$softDir/nginx/sbin/nginx -s reload
ExecStop=$softDir/nginx/sbin/nginx -s stop

[Install]
WantedBy=multi-user.target
EOF

# logrotate
cat > /etc/logrotate.d/nginx <<EOF
$logDir/nginx/*.log {
	daily
	dateext
	missingok
	rotate 2
	compress
	notifempty
	create 640 www www
	sharedscripts
	postrotate
		if [ -f $softDir/nginx/logs/nginx.pid ]; then 
			kill -USR1 \`cat $softDir/nginx/logs/nginx.pid\`
			\`cp -f $logDir/nginx/*.* $backupDir/log/nginx\`
		fi
	endscript
}
EOF
sed -i 's/error_log /data/log/nginx/error.log crit;/error_log "'$dir'"/log/nginx/error.log crit;/g' $softDir/nginx/conf/nginx.conf
sed -i 's/pid /data/soft/nginx/logs/nginx.pid;/pid "'$dir'"/soft/nginx/logs/nginx.pid;/g' $softDir/nginx/conf/nginx.conf

echo "59 23 * * *  /usr/sbin/logrotate -f /etc/logrotate.d/nginx" >> /var/spool/cron/root 

# 开机启动
systemctl enable nginx.service
# 启动nginx服务
systemctl start nginx.service

cp -R $currentDir/nginx/nginx /etc/init.d/nginx
chmod +x /etc/init.d/nginx


# 配置nginx目录
chmod 775 $softDir/nginx/logs
chown -R www:www $softDir/nginx/logs
chmod -R 775 $wwwDir
chown -R www:www $wwwDir
sleep 5


cd $shellDir/tools
# 安装php
if [ ! -f epel-release-latest-7.noarch.rpm ]; then
	# http://archive.fedoraproject.org/pub/epel/
	wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -O  $shellDir/tools/epel-release-latest-7.noarch.rpm
fi
rpm -ivh $shellDir/tools/epel-release-latest-7.noarch.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7

yum -y install autoconf libxml2 libxml2-devel curl-devel libjpeg libjpeg-devel libpng libpng-devel freetype freetype-devel gmp-devel libicu libicu-devel libmcrypt libmcrypt-devel libxslt-devel

if [ ! -f php-7.1.13.tar.gz ]; then
	wget http://hk1.php.net/get/php-7.1.13.tar.gz/from/this/mirror -O php-7.1.13.tar.gz
fi
tar -xzvf php-7.1.13.tar.gz
cd php-7.1.13
./configure --prefix=$softDir/php \
--with-config-file-path=$softDir/php/etc \
--with-fpm-user=www \
--with-fpm-group=www \
--disable-debug \
--disable-phpdbg \
--enable-mysqlnd \
--with-curl \
--enable-fpm \
--with-freetype-dir \
--with-gd \
--enable-gd-native-ttf \
--with-jpeg-dir \
--enable-mbstring \
--with-mcrypt \
--with-openssl \
--with-pdo-mysql=mysqlnd \
--with-png-dir \
--enable-soap \
--enable-sockets \
--with-zlib \
--enable-zip \
--with-mysqli=mysqlnd \
--enable-calendar \
--with-gettext=/usr \
--with-gmp \
--with-iconv \
--enable-intl \
--enable-pcntl \
--enable-shmop \
--enable-sysvmsg \
--enable-sysvsem \
--enable-sysvshm \
--enable-wddx \
--with-xmlrpc \
--with-xsl \
--with-iconv-dir \
--with-libxml-dir \
--with-mhash \
--enable-simplexml \
--enable-xml \
--enable-bcmath \
--enable-opcache \
--disable-rpath \

make && make install
#
## 配置php
cp ./php.ini-development $softDir/php/etc/php.ini
# 备份配置文件
cp $softDir/php/etc/php.ini $softDir/php/etc/php.ini.default

## php.ini
sed -i 's#; extension_dir = \"\.\/\"#extension_dir = "'$softDir'/php/lib/php/extensions/no-debug-non-zts-20160303/"#'  $softDir/php/etc/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 64M/g' $softDir/php/etc/php.ini
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 64M/g' $softDir/php/etc/php.ini
sed -i 's/;date.timezone =/date.timezone = Asia\/Shanghai/g' $softDir/php/etc/php.ini
sed -i 's/max_execution_time = 30/max_execution_time = 300/g' $softDir/php/etc/php.ini
sed -i 's/expose_php = On/expose_php = Off/g' $softDir/php/etc/php.ini
sed -i 's/display_errors = On/display_errors = Off/g' $softDir/php/etc/php.ini
sed -i 's/error_reporting = E_ALL/error_reporting = E_WARING \& ERROR/g' $softDir/php/etc/php.ini
sed -i 's/expose_php = On/expose_php = Off/g' $softDir/php/etc/php.ini

# redis
# sed -i 's/session.save_handler = files/session.save_handler = redis/g' $softDir/php/etc/php.ini
# sed -i 's/;session.save_path = "\/tmp"/session.save_path = "tcp:\/\/192.168.199.191:6379?auth=LJbrRajW9iBq\&database=1"/g' $softDir/php/etc/php.ini
# opcache
echo -e "\n[Opcache]" >> $softDir/php/etc/php.ini
echo "zend_extension=opcache.so" >> $softDir/php/etc/php.ini
echo "opcache.enable=1" >> $softDir/php/etc/php.ini
echo "opcache.enable_cli=1" >> $softDir/php/etc/php.ini
echo "opcache.fast_shutdown=1" >> $softDir/php/etc/php.ini

cp $softDir/php/etc/php-fpm.conf.default $softDir/php/etc/php-fpm.conf
cp $softDir/php/etc/php-fpm.d/www.conf.default $softDir/php/etc/php-fpm.d/www.conf

sed -i 's,user = nobody,user=www,g'   $softDir/php/etc/php-fpm.d/www.conf
sed -i 's,group = nobody,group=www,g'   $softDir/php/etc/php-fpm.d/www.conf
sed -i 's,^pm.min_spare_servers = 1,pm.min_spare_servers = 5,g'   $softDir/php/etc/php-fpm.d/www.conf
sed -i 's,^pm.max_spare_servers = 3,pm.max_spare_servers = 35,g'   $softDir/php/etc/php-fpm.d/www.conf
sed -i 's,^pm.max_children = 5,pm.max_children = 100,g'   $softDir/php/etc/php-fpm.d/www.conf
sed -i 's,^pm.start_servers = 2,pm.start_servers = 20,g'   $softDir/php/etc/php-fpm.d/www.conf
# sed -i 's,;pid = run/php-fpm.pid,pid = run/php-fpm.pid,g'   $softDir/php/etc/php-fpm.d/www.conf
# sed -i 's,;error_log = log/php-fpm.log,error_log = '$softDir'/log/php/php-fpm.log,g'   $softDir/php/etc/php-fpm.d/www.conf
sed -i 's,;slowlog = log/$pool.log.slow,slowlog = '$softDir'/log/php/\$pool.log.slow,g'   $softDir/php/etc/php-fpm.d/www.conf

install -v -m755 ./sapi/fpm/init.d.php-fpm  /etc/init.d/php-fpm
# 配置php-fpm服务
cat > /usr/lib/systemd/system/php-fpm.service <<EOF
[Unit]
Description=php-fpm
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
ExecStart=/etc/init.d/php-fpm start
ExecReload=/etc/init.d/php-fpm reload
ExecStop=/etc/init.d/php-fpm stop

[Install]
WantedBy=multi-user.target
EOF
# 开机启动
systemctl enable php-fpm.service

##扩展php
cd $shellDir/tools
### 1. redis
if [ ! -f redis-3.1.6.tgz ]; then
	wget http://pecl.php.net/get/redis-3.1.6.tgz -O redis-3.1.6.tgz
fi
tar -xzvf redis-3.1.6.tgz
cd redis-3.1.6
$softDir/php/bin/phpize
./configure --with-php-config=$softDir/php/bin/php-config
make && make install
echo -e "\n[Redis]" >> $softDir/php/etc/php.ini
echo "extension=redis.so" >> $softDir/php/etc/php.ini

cd $shellDir/tools
### 2. memcached
# --------------------------------------------------------------
#if [ ! -f msgpack-2.0.2.tgz ]; then
#	yum install -y msgpack-devel
#	wget http://pecl.php.net/get/msgpack-2.0.2.tgz -O 	msgpack-2.0.2.tgz
#fi
#tar -xzvf msgpack-2.0.2.tgz
#cd msgpack-2.0.2
#$softDir/php/bin/phpize
#./configure --with-php-config=$softDir/php/bin/php-config --with-msgpack
#make && make install
#echo -e "\n[msgpack]" >> $softDir/php/etc/php.ini
#echo "extension=msgpack.so" >> $softDir/php/etc/php.ini
# --------------------------------------------------------------

# --------------------------------------------------------------
#if [ ! -f igbinary-2.0.5.tgz ]; then
#	yum install -y msgpack-devel
#	wget http://pecl.php.net/get/igbinary-2.0.5.tgz -O 	igbinary-2.0.5.tgz
#fi
#tar -xzvf igbinary-2.0.5.tgz
#cd igbinary-2.0.5
#$softDir/php/bin/phpize
#./configure --with-php-config=$softDir/php/bin/php-config --with-igbinary
#make && make install
#echo -e "\n[igbinary]" >> $softDir/php/etc/php.ini
#echo "extension=igbinary.so" >> $softDir/php/etc/php.ini
# --------------------------------------------------------------

# --------------------------------------------------------------
if [ ! -f memcached-3.0.4.tgz ]; then
	yum install -y libevent-devel libmemcached-devel
	wget http://pecl.php.net/get/memcached-3.0.4.tgz -O memcached-3.0.4.tgz
fi
tar -xzvf memcached-3.0.4.tgz
cd memcached-3.0.4
$softDir/php/bin/phpize
./configure --with-php-config=$softDir/php/bin/php-config --with-libmemcached-dir
make && make install
echo -e "\n[Memcached]" >> $softDir/php/etc/php.ini
echo "extension=memcached.so" >> $softDir/php/etc/php.ini
# --------------------------------------------------------------

# 启动php-fpm服务
systemctl start php-fpm.service

sleep 5

cd $shellDir/tools

# 配置环境变量
echo "export PATH=\$PATH:$softDir/php/bin" >> /etc/profile

# 开启80端口
firewall-cmd --zone=public --add-port=80/tcp --permanent

# firewalld.service服务
firewall-cmd --reload


# 输出信息
echo "-----------------------------------"
echo "Install Directory"
echo "-----------------------------------"
echo "Nginx: $softDir/nginx"
echo "PHP: $softDir/php"
echo "-----------------------------------"