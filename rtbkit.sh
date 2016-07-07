#!/bin/bash

echo 'RTBkit ubuntu installation script';
echo 'This script will install all of the core dependencies of RTBkit and build it successfully';

echo "Installing dependencies: git, ngnix, core, zookeeper...";
sudo apt-get install linux-tools-generic libbz2-dev python-dev scons libtool liblzma-dev libblas-dev make automake ccache ant openjdk-7-jdk libcppunit-dev doxygen libcrypto++-dev libACE-dev gfortran liblapack-dev libevent-dev libssh2-1-dev libicu-dev libv8-dev g++ google-perftools libgoogle-perftools-dev zlib1g-dev git pkg-config valgrind autoconf libcurl4-openssl-dev cmake libsigc++-2.0-dev zookeeper zookeeperd redis-server graphite-carbon graphite-web nginx uwsgi uwsgi-plugin-python

sudo echo "CARBON_CACHE_ENABLED=true"  >> /etc/default/graphite-carbon

sudo cat <<EOF >> /usr/share/graphite-web/graphite.ini 
	[uwsgi]
	buffer-size = 65535
	socket = 127.0.0.1:9001
	wsgi-file = /usr/share/graphite-web/graphite.wsgi
	processes = 4
	plugin = python

EOF

sudo cat <<EOF >> /etc/init.d/graphite
	#!/bin/bash
	 
	### BEGIN INIT INFO
	# Provides:          graphite
	# Required-Start:    $all
	# Required-Stop:     $all
	# Default-Start:     2 3 4 5
	# Default-Stop:      0 1 6
	# Short-Description: starts the graphite uwsgi app server
	# Description:       starts graphite app server using start-stop-daemon
	### END INIT INFO
	 
	PATH=/opt/uwsgi:/sbin:/bin:/usr/sbin:/usr/bin
	DAEMON=/usr/bin/uwsgi
	 
	OWNER=_graphite
	 
	NAME=uwsgi
	DESC=uwsgi
	 
	test -x $DAEMON || exit 0
	 
	# Include uwsgi defaults if available
	if [ -f /etc/default/uwsgi-graphite ] ; then
	       ". /etc/default/uwsgi-graphite
	fi
	 
	set -e
	 
	APPNAME=graphite
	BASEPATH=/var/lib/graphite
	PIDFILE=$BASEPATH/graphite.pid
	 
	DAEMON_OPTS=\"$VENV_ARG --ini /usr/share/graphite-web/graphite.ini --stats /tmp/uwsgi-stats-${APPNAME}.soc-need-app --lazy --master --pidfile $PIDFILE --daemonize $BASEPATH/graphite.log\"
	 
	function do_start {
	        start-stop-daemon --start --pid $PIDFILE --chuid $OWNER:$OWNER --user $OWNER --exec $DAEMON -DAEMON_OPTS
	}
	 
	function do_stop {
	        start-stop-daemon --signal QUIT --pid $PIDFILE --user $OWNER --quiet --retry 2 --stop  --oknodo
	}
	case \"$1\" in
	  start)
	        echo -n \"Starting $DESC: \"
	        do_start
	        echo \"$NAME.\"
	        ;;
	  stop)
	        echo -n \"Stopping $DESC: \"
	        do_stop
	        echo \"$NAME.\"
	        ;;
	  restart)
	        echo -n \"Restarting $DESC: \"
	        do_stop
	        sleep 1
	        do_start
	        echo \"$NAME.\"
	        ;;
	  status)
	        killall -10 $DAEMON
	        ;;
	      *)
	            N=/etc/init.d/$NAME
	            echo \"Usage: $N {start|stop|restart|reload|force-reload|status}\" >&2
	            exit 1
	            ;;
	    esac
	    exit 
EOF

sudo cat <<EOF >> /home/rtbkit/.profile
	# Add local directory for libraries, etc
	HOME=/home/rtbkit
	mkdir -p $HOME/local/bin
	PATH="$HOME/local/bin:$PATH"
	mkdir -p $HOME/local/lib
	export LD_LIBRARY_PATH="$HOME/local/lib:$LD_LIBRARY_PATH"
	export PKG_CONFIG_PATH="$HOME/local/lib/pkgconfig/:$HOME/local/lib/pkg-config/"
EOF

sudo cat <<EOF >> /etc/init/rtbkit-mock.conf
	description "RTBkit Mock Exchange"
	limit nofile 32768 32768
	start on runlevel [2345]
	stop on runlevel [!2345]
	respawn
	respawn limit 2 5
	umask 007
	kill timeout 300
	setuid rtbkit
	setgid rtbkit
	chdir /home/rtbkit/rtbkit/
	script
	/bin/bash -c 'source /home/rtbkit/.profile && ./build/x86_64/bin/mock_exchange_runner'
	end script

EOF

sudo cat <<EOF >> /etc/init/rtbkit.conf
	description "RTBkit"
	limit nofile 32768 32768
	start on runlevel [2345]
	stop on runlevel [!2345]
	respawn
	respawn limit 2 5
	umask 007
	kill timeout 300
	setuid rtbkit
	setgid rtbkit
	chdir /home/rtbkit/rtbkit/
	script
	/bin/bash -c 'source /home/rtbkit/.profile && ./build/x86_64/bin/launcher --node localhost --script ./launch.sh tbkit/sample.launch.json && ./launch.sh'
	end script
	
EOF

sudo cat <<EOF >> /etc/nginx/sites-enabled/quickboard.conf
	server {
	listen 80;
	access_log /var/log/nginx/quickboard.access.log;
	error_log /var/log/nginx/quickboard.error.log;
	root /var/www/quickboard/;
	}
EOF

sudo cat <<EOF >> /etc/nginx/sites-enabled/graphite.conf
	server {
	    listen 4888;
	    access_log /var/log/nginx/graphite.access.log;
	    error_log /var/log/nginx/graphite.error.log;
	    client_max_body_size 4M;
	    client_body_buffer_size 128k;
	    expires 10s;
	    root html;
	    index index.html index.htm;
	    location / {
	        uwsgi_pass 127.0.0.1:9001;
	        uwsgi_read_timeout 60;
	        include /etc/nginx/uwsgi_params;
	        add_header Access-Control-Allow-Origin *;
	    }
	}

EOF

su _graphite -s /bin/bash -c '/usr/bin/python /usr/lib/python2.7/dist-packages/graphite/manage.py syncdb --noinput'

cd /home/rtbkit
sudo chown -v rtbkit /home/rtbkit
su rtbkit -s /bin/bash -c 'echo $HOME > /home/rtbkit/home.txt'
su rtbkit -s /bin/bash -c 'git clone https://github.com/rtbkit/rtbkit-deps.git'
su rtbkit -s /bin/bash -c 'git submodule update --init'
su rtbkit -s /bin/bash -c 'source ~/.profile && make all NODEJS_ENABLED=0'
su rtbkit -s /bin/bash -c 'git clone https://github.com/rtbkit/rtbkit.git'

cd /home/rtbkit/rtbkit
su rtbkit -s /bin/bash -c 'git checkout ubuntu14'

cd
ulimit -S 65536

cd /home/rtbkit/rtbkit
su rtbkit -s /bin/bash -c 'cp jml-build/sample.local.mk local.mk && source ~/.profile && make -j8 NODEJS_ENABLED=0 compile'

cd /home/rtbkit/rtbkit/rtbkit
su rtbkit -s /bin/bash -c 'sed -i \"s/\\/\\/ \\\"carbon-uri\\\".*$/\\\"carbon-uri\\\"\\: \\[\\\"127.0.0.1\\:2003\\\"\\],/\" sample.bootstrap.json

cd /home/rtbkit
su rtbkit -s /bin/bash -c 'git clone https://github.com/rtbkit/quickboard.git'

cd /home/rtbkit/quickboard
rm -f /etc/nginx/sites-enabled/default ; mkdir -p /var/www/quickboard && cp index.html /var/www/quickboard/

cd /var/www/quickboard
sed -i "s/^.*graphite\\.host.*$/host:\\\"http:\\/\\/`curl 169.254.169.254/latest/meta-data/public-ipv4`:4888\\\", prefix:\\\"rtb-test\\\",/" index.html

sed -i "s/^.*graphite\\.host.*$/host:\\\"http:\\/\\/`curl 169.254.169.254/latest/meta-data/public-ipv4`:4888\\\", prefix:\\\"rtb-test\\\",/" index.html

/etc/init.d/nginx reload

/sbin/start rtbkit-mock ; /sbin/start rtbkit




