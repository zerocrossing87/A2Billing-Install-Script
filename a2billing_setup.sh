#!/bin/bash

#####################################################################
#
#
#	Created by Andres Montalban - amontalban <AT> amtechhelp.com
#	Last update - 28-12-2011
#
#
#####################################################################

####################### CONFIGURATION VALUES #########################

A2BILLING_VERSION="v1.9.4"
WORK_DIRECTORY="/usr/src"
OK_MSG="\E[1;32m[OK]"
ERROR_MSG="\E[1;31m[ERROR]"
LOG_FILE="/var/log/a2billing_install"
ADDITIONAL_PACKAGES="php php-mcrypt php-gd php-mysql php mysql-server"
HTTP_USER="apache"
ETC_DIRECTORY="/etc"
ASTERISK_CONFIG_DIRECTORY="/etc/asterisk"
HTTP_CONFIG_DIRECTORY="/etc/httpd/conf"
ASTERISK_DIRECTORY="/var/lib/asterisk"
ASTERISK_MODULES_DIRECTORY="/usr/lib/asterisk/modules"
ASTERISK_USER="asterisk"
WWW_ROOT="/var/www/html"
HOSTNAME=`hostname`
SERVER_IP=`ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{print $1}'`
CURRENT_DIR=$PWD
UNWANTED_SERVICES="cups bluetooth avahi-daemon avahi-daemon dnsconfd gpm haldaemon hidd nfslock netfs iscsi iscsid autofs portmap yum-updatesd pcscd rpcgssd rpcidmapd sendmail"

######################################################################
################## DO NOT EDIT BEYOND THIS LINE ######################
######################################################################

########################### HANDY FUNCTIONS ##########################

# Log the text in parameter to $LOG_FILE
function logEvent {
	local STRING=$1
	log_daemon_msg $STRING
	echo $STRING >> $LOG_FILE
}

function displayMessage {
	local MESSAGE=$1

	echo -n "$MESSAGE... "
}

function displayResult {
	local RESULT=$1

	if [ $RESULT -eq 0 ]; then
		echo -e "$OK_MSG"
		tput sgr0
	else
		echo -e "$ERROR_MSG"
		tput sgr0
		echo "For more information about the error please check the logfile at $LOG_FILE"
		exit 1
	fi
}

function yes_no {
	echo -n "$1"
	read ans
	case "$ans" in
	y|Y|yes|YES|Yes) return 0 ;;
	n|N|no|NO|No) return 1 ;;
	*) return 2 ;;
	esac
}

######################################################################

# We check that the script is running on a screen session before doing anything
echo "Checking that the script is running on a screen session"
if [ -z "$STY" ]; then
	echo
	echo -e "\E[1;31mThis install process takes several minutes, so it's possible that you loose connection while executing this script therefore is HIGHLY RECOMMENDED that you run this script on a screen session, to do this please execute \"screen\" (Without the quotes) and run the script again."
	tput sgr0
	echo
	echo
	SCREEN_INSTALLED=`rpm -qa screen`
	if [ -z $SCREEN_INSTALLED ]; then
		echo "It seems that the screen package isn't installed, in order to install you need to execute: yum -y install screen"
		echo
		echo
	fi
	exit 1
else
	echo -e "\E[1;32mScreen session detected, starting installation script..."
	tput sgr0
fi

# We clean the logfile
echo > $LOG_FILE

if ! [ -e $WORK_DIRECTORY ]; then
	displayMessage "Creating work directory at $WORK_DIRECTORY"
	mkdir -p $WORK_DIRECTORY >> $LOG_FILE 2>&1
	displayResult $?
else
	displayMessage "Work directory $WORK_DIRECTORY already exists"
	displayResult 0
fi

# Checking Internet connectivity
displayMessage "Checking Internet connectivity"
ping -c 3 www.google.com >> $LOG_FILE 2>&1
INTERNET_CONNECTION=$?

if [ $INTERNET_CONNECTION -gt 0 ]; then
	displayResult 1
	echo -e "\E[1;31mCan't continue with installation, please check Internet connection!"
	tput sgr0	
else
	displayResult 0
fi

# We check that we are running CentOS 5
displayMessage "Checking that the server is running CentOS 5"
CENTOS_RELEASE=`rpm -qa centos-release | awk -F- '{print $3}'`

if [ $CENTOS_RELEASE -eq "5" ]; then
	displayResult 0
else
	displayResult 1
fi

# We enable CentOS Update repository
displayMessage "Yum updates repository configuration"
sed -i '/\[updates\]/a enabled=1' /etc/yum.repos.d/CentOS-Base.repo
displayResult $?

# We disable the use of PHP 5.3
displayMessage "Disabling PHP 5.3 in yum"
sed -i '/\[base\]/a exclude=php53*' /etc/yum.repos.d/CentOS-Base.repo
displayResult $?

# We import RPMForge GPG keys
displayMessage "Importing RPMForge GPG Keys"
rpm --import http://apt.sw.be/RPM-GPG-KEY.dag.txt >> $LOG_FILE 2>&1
displayResult $?

# We import CentOS 5 GPG keys
displayMessage "Importing CentOS 5 GPG Keys"
rpm --import http://ftp.osuosl.org/pub/centos/RPM-GPG-KEY-CentOS-5 >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Updating system packages"
yum -y update >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Disabling SELinux"
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Disabling firewall - Step 1 of 2"
chkconfig --level 2345 iptables off >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Disabling firewall - Step 2 of 2"
chkconfig --level 2345 ip6tables off >> $LOG_FILE 2>&1
displayResult $?

echo "Removing old kernels..."
kernels=`rpm -q kernel | wc -l`
if [ $kernels -eq 1 ]; then
	displayMessage "Only one kernel found, not removing it"
else
	rpm -q kernel | sed '$d' > kernel_list
	while read line;
	do
		displayMessage "Removing kernel $line"
		yum -y remove $line >> $LOG_FILE 2>&1
		displayResult $?
	done < kernel_list
fi

displayMessage "The following additional packages will be installed"
echo ""
for package in $ADDITIONAL_PACKAGES
do
	echo " - $package"
done

displayMessage "Installing additional packages"
yum -y install $ADDITIONAL_PACKAGES >> $LOG_FILE 2>&1
displayResult $?

echo "Please enter the desired MySQL Root password, followed by [ENTER]:"
MYSQL_ROOT_PASSWORD_VALIDATED=false
while [ ${MYSQL_ROOT_PASSWORD_VALIDATED} == false ]; do

	MYSQL_ROOT_PASSWORD_1=""
	while [ -z "${MYSQL_ROOT_PASSWORD_1}" ]; do
		read -s MYSQL_ROOT_PASSWORD_1
		if [ -z "${MYSQL_ROOT_PASSWORD_1}" ]; then
			echo "Please enter the desired MySQL Root password, followed by [ENTER]:"
		fi
	done

	echo "Please re-enter the desired MySQL Root password to verify it, followed by [ENTER]:"
	MYSQL_ROOT_PASSWORD_2=""
	while [ -z "${MYSQL_ROOT_PASSWORD_2}" ]; do
		read -s MYSQL_ROOT_PASSWORD_2
		if [ -z "${MYSQL_ROOT_PASSWORD_2}" ]; then
			echo "Please re-enter the desired MySQL Root password to verify it, followed by [ENTER]:"
		fi
	done

	if [ "${MYSQL_ROOT_PASSWORD_1}" == "${MYSQL_ROOT_PASSWORD_2}" ]; then
		MYSQL_ROOT_PASSWORD_VALIDATED=true
		MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD_1
	else
		echo
		echo
		echo
		echo -e "\E[1;31m		PASSWORDS DOESN'T MATCH!!!"
		tput sgr0
		echo
		echo
		echo
		echo "Please enter the desired MySQL Root password, followed by [ENTER]:"
	fi

done

echo "Please enter the desired MySQL password for A2Billing user, followed by [ENTER]:"
MYSQL_A2BILLING_PASSWORD_VALIDATED=false
while [ ${MYSQL_A2BILLING_PASSWORD_VALIDATED} == false ]; do

	MYSQL_A2BILLING_PASSWORD_1=""
	while [ -z "${MYSQL_A2BILLING_PASSWORD_1}" ]; do
		read -s MYSQL_A2BILLING_PASSWORD_1
		if [ -z "${MYSQL_A2BILLING_PASSWORD_1}" ]; then
			echo "Please enter the desired MySQL password for A2Billing user, followed by [ENTER]:"
		fi
	done

	echo "Please re-enter the desired MySQL password for A2Billing to verify it, followed by [ENTER]:"
	MYSQL_A2BILLING_PASSWORD_2=""
	while [ -z "${MYSQL_A2BILLING_PASSWORD_2}" ]; do
		read -s MYSQL_A2BILLING_PASSWORD_2
		if [ -z "${MYSQL_A2BILLING_PASSWORD_2}" ]; then
			echo "Please re-enter the desired MySQL password for A2Billing to verify it, followed by [ENTER]:"
		fi
	done

	if [ "${MYSQL_A2BILLING_PASSWORD_1}" == "${MYSQL_A2BILLING_PASSWORD_2}" ]; then
		MYSQL_A2BILLING_PASSWORD_VALIDATED=true
		MYSQL_A2BILLING_PASSWORD=$MYSQL_A2BILLING_PASSWORD_1
	else
		echo
		echo
		echo
		echo -e "\E[1;31m		PASSWORDS DOESN'T MATCH!!!"
		tput sgr0
		echo
		echo
		echo
		echo "Please enter the desired MySQL password for A2Billing user, followed by [ENTER]:"
	fi

done

# Configure handy MySQL commands for later use
MYSQL_EXECUTE="mysql -u root -p$MYSQL_ROOT_PASSWORD -e"
MYSQL_EXECUTE_A2BILLING="mysql -u root -p$MYSQL_ROOT_PASSWORD mya2billing -e"

displayMessage "Configuring MySQL Service"
sed -i '/\[mysqld\]/a bind-address=127.0.0.1' $ETC_DIRECTORY/my.cnf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Enabling MySQL service to start on boot"
chkconfig --level 2345 mysqld on >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Starting MySQL service"
service mysqld start >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Checking if MySQL service started"
netstat -nlt | grep :3306 >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing MySQL root password - Step 1"
mysqladmin -u root password $MYSQL_ROOT_PASSWORD >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing MySQL root password - Step 2"
$MYSQL_EXECUTE "update mysql.user set Password = PASSWORD('$MYSQL_ROOT_PASSWORD') where User = 'root';" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing MySQL root password - Step 3"
$MYSQL_EXECUTE "update mysql.user set Password = PASSWORD('$MYSQL_ROOT_PASSWORD') where Password = '';" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring HTTP Service"
sed -i '/ldap/d' $HTTP_CONFIG_DIRECTORY/httpd.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Enabling HTTP service to start on boot"
chkconfig --level 2345 httpd on >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Starting HTTP service"
service httpd start >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Checking if HTTP service started"
netstat -nlt | grep :80 >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Downloading A2Billing script version $A2BILLING_VERSION"
wget -t 3 --no-check-certificate https://github.com/Star2Billing/a2billing/tarball/$A2BILLING_VERSION -O $WORK_DIRECTORY/A2Billing_$A2BILLING_VERSION.tar.gz >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Extracting A2Billing script in $WORK_DIRECTORY"
A2BILLING_DIRECTORY=`tar -tzf $WORK_DIRECTORY/A2Billing_$A2BILLING_VERSION.tar.gz | head -1 | sed 's/\///g'`
tar -zxvf $WORK_DIRECTORY/A2Billing_$A2BILLING_VERSION.tar.gz -C $WORK_DIRECTORY >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Moving A2Billing from $WORK_DIRECTORY/$A2BILLING_DIRECTORY to $WORK_DIRECTORY/a2billing"
mv $WORK_DIRECTORY/$A2BILLING_DIRECTORY $WORK_DIRECTORY/a2billing >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing MySQL import file"
sed -i "s/'a2billing'/'$MYSQL_A2BILLING_PASSWORD'/g" $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/a2billing-createdb-user.sql >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating A2Billing MySQL Database user"
mysql -u root -p$MYSQL_ROOT_PASSWORD < $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/a2billing-createdb-user.sql >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Removing MySQL A2Billing password in MySQL import file for security"
sed -i "s/$MYSQL_A2BILLING_PASSWORD/PASSWORD_CHANGED_FOR_SECURITY/g" $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/a2billing-createdb-user.sql >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing MySQL Database importer script - Step 1"
sed -i '/echo/d' $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing MySQL Database importer script - Step 2"
sed -i '/read/d' $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing MySQL Database importer script - Step 3"
sed -i 's/$username/root/g' $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing MySQL Database importer script - Step 4"
sed -i "s/\$password/$MYSQL_ROOT_PASSWORD/g" $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing MySQL Database importer script - Step 5"
sed -i "s/\$hostname/localhost/g" $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing MySQL Database importer script - Step 6"
sed -i "s/\$dbname/mya2billing/g" $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing directory to $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x"
cd $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/ >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Executing A2Billing MySQL Loader"
$WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Removing MySQL root password in A2Billing MySQL loader for security"
sed -i "s/$MYSQL_ROOT_PASSWORD/PASSWORD_CHANGED_FOR_SECURITY/g" $WORK_DIRECTORY/a2billing/DataBase/mysql-5.x/install-db.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Linking A2Billing configuration file from $WORK_DIRECTORY/a2billing/a2billing.conf to $ETC_DIRECTORY/a2billing.conf"
ln -s $WORK_DIRECTORY/a2billing/a2billing.conf $ETC_DIRECTORY/a2billing.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing configuration file - Step 1"
sed -i 's/a2billing_dbuser/a2billinguser/g' $ETC_DIRECTORY/a2billing.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing configuration file - Step 2"
sed -i "s/a2billing_dbpassword/$MYSQL_A2BILLING_PASSWORD/g" $ETC_DIRECTORY/a2billing.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing configuration file - Step 3"
sed -i 's/a2billing_dbname/mya2billing/g' $ETC_DIRECTORY/a2billing.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing configuration file - Step 4"
sed -i 's/port =/port = 3306/g' $ETC_DIRECTORY/a2billing.conf >> $LOG_FILE 2>&1
displayResult $?

echo "Configuring Asterisk & Digium Repositories..."
echo "Detecting system arquitecture..."

ARCH=`uname -i`
displayMessage "System arquitecture detected: $ARCH"
displayResult $?

displayMessage "Downloading Asterisk & Digium Repositories"
wget http://packages.asterisk.org/centos/5/current/$ARCH/RPMS/asterisknow-version-1.7.1-3_centos5.noarch.rpm >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Installing Asterisk & Digium Repositories"
yum --nogpgcheck -y localinstall asterisknow-version-1.7.1-3_centos5.noarch.rpm >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Deleting downloaded files"
rm -f asterisknow-version-1.7.1-3_centos5.noarch.rpm >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Installing Asterisk"
yum -y install asterisk16 asterisk16-configs dahdi-linux dahdi-tools libpri >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing $ASTERISK_CONFIG_DIRECTORY/sip.conf file format from DOS to Unix"
dos2unix $ASTERISK_CONFIG_DIRECTORY/sip.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing $ASTERISK_CONFIG_DIRECTORY/extensions.conf file format from DOS to Unix"
dos2unix $ASTERISK_CONFIG_DIRECTORY/extensions.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing $ASTERISK_CONFIG_DIRECTORY/iax.conf file format from DOS to Unix"
dos2unix $ASTERISK_CONFIG_DIRECTORY/iax.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating A2Billing IAX configuration file"
touch $ASTERISK_CONFIG_DIRECTORY/additional_a2billing_iax.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating A2Billing SIP configuration file"
touch $ASTERISK_CONFIG_DIRECTORY/additional_a2billing_sip.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Including A2Billing SIP configuration file to Asterisk configuration"
echo "#include additional_a2billing_sip.conf" >> $ASTERISK_CONFIG_DIRECTORY/sip.conf
displayResult $?

displayMessage "Including A2Billing IAX configuration file to Asterisk configuration"
echo "#include additional_a2billing_iax.conf" >> $ASTERISK_CONFIG_DIRECTORY/iax.conf
displayResult $?

displayMessage "Changing ownership of A2Billing IAX configuration file"
chown -Rf $HTTP_USER:$HTTP_USER $ASTERISK_CONFIG_DIRECTORY/additional_a2billing_iax.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing ownership of A2Billing SIP configuration file"
chown -Rf $HTTP_USER:$HTTP_USER $ASTERISK_CONFIG_DIRECTORY/additional_a2billing_sip.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing directory to $WORK_DIRECTORY/a2billing/addons/sounds"
cd $WORK_DIRECTORY/a2billing/addons/sounds >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Executing A2Billing sounds installation"
$WORK_DIRECTORY/a2billing/addons/sounds/install_a2b_sounds.sh >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing ownership of Asterisk sound files"
chown -R $ASTERISK_USER:$ASTERISK_USER $ASTERISK_DIRECTORY/sounds >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring Asterisk Manager - Step 1"
sed -i 's/enabled = no/enabled = yes/g' $ASTERISK_CONFIG_DIRECTORY/manager.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring Asterisk Manager - Step 2"
sed -i 's/bindaddr = 0.0.0.0/bindaddr = 127.0.0.1/g' $ASTERISK_CONFIG_DIRECTORY/manager.conf >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring Asterisk Manager - Step 3"
displayMessage "Adding A2Billing dialplan configuration to $ASTERISK_CONFIG_DIRECTORY/extensions.conf"
echo "

[myasterisk]
secret=mycode
read=system,call,log,verbose,command,agent,user
write=system,call,log,verbose,command,agent,user
" >> /etc/asterisk/manager.conf
displayResult $?

displayMessage "Changing ownership for AGI-Bin directory"
chown $ASTERISK_USER:$ASTERISK_USER $ASTERISK_DIRECTORY/agi-bin >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Linking $WORK_DIRECTORY/a2billing/AGI/a2billing.php to $ASTERISK_DIRECTORY/agi-bin/a2billing.php"
ln -s $WORK_DIRECTORY/a2billing/AGI/a2billing.php $ASTERISK_DIRECTORY/agi-bin/a2billing.php >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Linking $WORK_DIRECTORY/a2billing/AGI/lib to $ASTERISK_DIRECTORY/agi-bin/lib"
ln -s $WORK_DIRECTORY/a2billing/AGI/lib /var/lib/asterisk/agi-bin/lib >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Setting execution permission to $ASTERISK_DIRECTORY/agi-bin/a2billing.php"
chmod +x $ASTERISK_DIRECTORY/agi-bin/a2billing.php >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating WEB directory $WWW_ROOT/billing"
mkdir -p $WWW_ROOT/billing >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing ownership of the WEB directory $WWW_ROOT/billing"
chown $HTTP_USER:$HTTP_USER $WWW_ROOT/billing >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Linking $WORK_DIRECTORY/a2billing/admin to $WWW_ROOT/billing/admin"
ln -s $WORK_DIRECTORY/a2billing/admin $WWW_ROOT/billing/admin >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Linking $WORK_DIRECTORY/a2billing/agent to $WWW_ROOT/billing/agent"
ln -s $WORK_DIRECTORY/a2billing/agent $WWW_ROOT/billing/agent >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Linking $WORK_DIRECTORY/a2billing/customer to $WWW_ROOT/billing/customer"
ln -s $WORK_DIRECTORY/a2billing/customer $WWW_ROOT/billing/customer >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Linking $WORK_DIRECTORY/a2billing/common to $WWW_ROOT/billing/common"
ln -s $WORK_DIRECTORY/a2billing/common $WWW_ROOT/billing/common >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing permissions to folder $WORK_DIRECTORY/a2billing/admin/templates_c"
chmod 755 $WORK_DIRECTORY/a2billing/admin/templates_c >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing permissions to folder $WORK_DIRECTORY/a2billing/admin/templates_c"
chmod 755 $WORK_DIRECTORY/a2billing/customer/templates_c >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing permissions to folder $WORK_DIRECTORY/a2billing/admin/templates_c"
chmod 755 $WORK_DIRECTORY/a2billing/agent/templates_c >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Change ownership of folder $WORK_DIRECTORY/a2billing/admin/templates_c"
chown -Rf $HTTP_USER:$HTTP_USER $WORK_DIRECTORY/a2billing/admin/templates_c >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Change ownership of folder $WORK_DIRECTORY/a2billing/customer/templates_c"
chown -Rf $HTTP_USER:$HTTP_USER $WORK_DIRECTORY/a2billing/customer/templates_c >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Change ownership of folder $WORK_DIRECTORY/a2billing/agent/templates_c"
chown -Rf $HTTP_USER:$HTTP_USER $WORK_DIRECTORY/a2billing/agent/templates_c >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating default web file to hide directory listing in billing directory"
touch $WWW_ROOT/billing/index.php >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing ownershipt of the file $WWW_ROOT/billing/index.php"
chown -Rf $HTTP_USER:$HTTP_USER $WWW_ROOT/billing/index.php >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Adding A2Billing dialplan configuration to $ASTERISK_CONFIG_DIRECTORY/extensions.conf"
echo "

[a2billing]
; CallingCard application
exten => _X.,1,Set(CALLERID(num)=\${CALLERID(NUM)})
exten => _X.,n,Set(DYNAMIC_FEATURES=)
exten => _X.,n,AGI(a2billing.php,1)
exten => _X.,n,NoOp(=================== HANGUPCAUSE-A2BILLING: \${EXTEN} = \${HANGUPCAUSE} ===================)
" >> /etc/asterisk/extensions.conf
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting answer_call=no in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 0 where config_key = \"answer_call\" and config_title = \"Answer Call\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting use_dnid=yes in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 1 where config_key = \"use_dnid\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting play_audio=no in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 0 where config_key = \"play_audio\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting asterisk_version=1_2 in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = \"1_6\" where config_key = \"asterisk_version\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting min_credit_2call=1 in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 1 where config_key = \"min_credit_2call\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting dialcommand_param=,60,HRrL(%timeout%) in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = \",60,RrL(%timeout%)\" where config_key = \"dialcommand_param\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting say_timetocall=no in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 0 where config_key = \"say_timetocall\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting dialcommand_param_sipiax_friend=,30, in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = \",30,\" where config_key = \"dialcommand_param_sipiax_friend\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting number_try=1 in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 1 where config_key = \"number_try\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting cid_enable=0 in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 0 where config_key = \"cid_enable\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring MySQL database mya2billing, setting use_realtime=0 in table cc_config"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = 0 where config_key = \"use_realtime\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring G729 as the only enabled codec for SIP/IAX peers created in A2Billing"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = \"g279\" where config_key = \"sip_iax_info_allowcodec\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring DID Dial to remove H and i parameters as they are not working properly"
$MYSQL_EXECUTE_A2BILLING "update cc_config set config_value = \",60,L(%timeout%:61000:30000)\" where config_key = \"dialcommand_param_call_2did\";" >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring A2Billing run directory"
mkdir -p /var/run/a2billing >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing ownership of the A2Billing run directory"
chown asterisk:asterisk /var/run/a2billing >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Configuring cronjobs..."
echo "
# Automatically added for A2Billing
0 * * * * php /usr/src/a2billing/Cronjobs/a2billing_alarm.php
# Archive call data at 3:00 AM (When load is low)
0 3 * * * php /usr/src/a2billing/Cronjobs/a2billing_archive_data_cront.php
0 10 21 * * php /usr/src/a2billing/Cronjobs/a2billing_autorefill.php
#Batch process at 00:20 each day
20 0 * * * php /usr/src/a2billing/Cronjobs/a2billing_batch_process.php
#Bill DID usage at 00:00 each day
0 0 * * * php /usr/src/a2billing/Cronjobs/a2billing_bill_diduse.php
#Generate Invoices at 6am everyday
0 6 * * * php /usr/src/a2billing/Cronjobs/a2billing_batch_billing.php
#Check if balance below preset value, and email user if so.
1 * * * * php /usr/src/a2billing/Cronjobs/a2billing_notify_account.php
#Charge subscriptions at 06:05 on the 1st of each month
0 6 1 * * php /usr/src/a2billing/Cronjobs/a2billing_subscription_fee.php
#Update currencies at 01:00 each day
0 1 * * * php /usr/src/a2billing/Cronjobs/currencies_update_yahoo.php
" >> /var/spool/cron/asterisk
displayResult $?

displayMessage "Creating /var/lib/a2billing/script folder..."
mkdir -p /var/lib/a2billing/script >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing folder..."
mkdir -p /var/log/a2billing >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/a2billing-daemon-callback.log logfile..."
touch /var/log/a2billing/a2billing-daemon-callback.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/cront_a2b_alarm.log logfile..."
touch /var/log/a2billing/cront_a2b_alarm.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/cront_a2b_autorefill.log logfile..."
touch /var/log/a2billing/cront_a2b_autorefill.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/cront_a2b_batch_process.log logfile..."
touch /var/log/a2billing/cront_a2b_batch_process.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/cront_a2b_bill_diduse.log logfile..."
touch /var/log/a2billing/cront_a2b_bill_diduse.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/cront_a2b_subscription_fee.log logfile..."
touch /var/log/a2billing/cront_a2b_subscription_fee.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/cront_a2b_currency_update.log logfile..."
touch /var/log/a2billing/cront_a2b_currency_update.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/cront_a2b_invoice.log logfile..."
touch /var/log/a2billing/cront_a2b_invoice.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/a2billing_paypal.log logfile..."
touch /var/log/a2billing/a2billing_paypal.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/a2billing_epayment.log logfile..."
touch /var/log/a2billing/a2billing_epayment.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/api_ecommerce_request.log logfile..."
touch /var/log/a2billing/api_ecommerce_request.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/api_callback_request.log logfile..."
touch /var/log/a2billing/api_callback_request.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Creating /var/log/a2billing/a2billing_agi.log logfile..."
touch /var/log/a2billing/a2billing_agi.log >> $LOG_FILE 2>&1
displayResult $?

displayMessage "Changing owner for folder /var/log/a2billing ..."
chown -R asterisk:asterisk /var/log/a2billing >> $LOG_FILE 2>&1
displayResult $?

echo "Disabling unneeded services..."
for service in $UNWANTED_SERVICES
do
	INIT_PATH="/etc/init.d/${service}"
	if [ -e $INIT_PATH ]; then
		displayMessage "Disabling service: $service ..."
		chkconfig --level 2345 $service off >> $LOG_FILE 2>&1
		displayResult $?
	else
		echo -e "\E[1;31mThe service $service is not present on this system so we can't disable it!"
		tput sgr0
	fi
done

yes_no "Do you want to install Sangoma Wanpipe Drivers? [Y/n] "
INSTALL_WANPIPE=$?

case $INSTALL_WANPIPE in
	0)
		echo ""
	;;

	1)
		echo ""
		echo "Not installing Sangoma drivers, please remember that if you add any Sangoma card you will have to install the drivers in order to use it."
		echo ""
	;;

	2)
		while [ $INSTALL_WANPIPE -gt 1 ]
		do
			yes_no "Do you want to install Sangoma Wanpipe Drivers? [Y/n] "
			INSTALL_WANPIPE=$?
		done
	;;
esac

if [ $INSTALL_WANPIPE -eq 0 ]; then
	displayMessage "Installing group \"Development Tools\""
	yum -y groupinstall "Development Tools" >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Installing required packages for Sangoma drivers installation"
	yum -y install kernel-devel libtool* gcc patch bison gcc-c++ ncurses-devel flex libtermcap-devel autoconf* automake*  >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Changing directory to /usr/src"
	cd /usr/src >> $LOG_FILE 2>&1
	displayResult $?

	echo "Detecting Dahdi installed version..."
	DAHDI_VERSION=`yum -q info dahdi-linux | grep Version | awk '{print $3}'` >> $LOG_FILE 2>&1
	displayMessage "Detected Dahdi version: $DAHDI_VERSION"
	displayResult $?

	displayMessage "Downloading Dahdi sources from Asterisk servers"
	wget http://downloads.asterisk.org/pub/telephony/dahdi-linux/releases/dahdi-linux-${DAHDI_VERSION}.tar.gz >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Decompressing Dahdi sources"
	tar -zxvf dahdi-linux-${DAHDI_VERSION}.tar.gz >> $LOG_FILE 2>&1
	displayResult $?
	
	displayMessage "Changing directory to /usr/src/dahdi-linux-$DAHDI_VERSION"
	cd dahdi-linux-${DAHDI_VERSION} >> $LOG_FILE 2>&1
	displayResult $?

	echo "Detecting kernel version..."
	KERNEL_VERSION=`rpm -qa kernel | sed 's/kernel-//g'`
	displayMessage "Detected Kernel version: $KERNEL_VERSION"
	displayResult $?

	displayMessage "Compiling Dahdi sources"
	make KVERS=$KERNEL_VERSION >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Changing directory to /usr/src"
	cd /usr/src >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Downloading latest Sangoma Wanpipe drivers from Sangoma servers"
	wget ftp://ftp.sangoma.com/linux/current_wanpipe/wanpipe-latest.tgz >> $LOG_FILE 2>&1
	displayResult $?

	echo "Detecting downloaded Sangoma Wanpipe drivers version..."
	WANPIPE_VERSION=`tar -tzf wanpipe-latest.tgz | head -1 | sed 's/\///g'` >> $LOG_FILE 2>&1
	displayMessage "Detected Sangoma Wanpipe drivers version: $WANPIPE_VERSION"
	displayResult $?

	displayMessage "Renaming Sangoma Wanpipe drivers file"
	mv wanpipe-latest.tgz ${WANPIPE_VERSION}.tgz  >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Decompressing Sangoma Wanpipe drivers"
	tar -xvzf ${WANPIPE_VERSION}.tgz >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Changing directory to /usr/src/$WANPIPE_VERSION"
	cd ${WANPIPE_VERSION} >> $LOG_FILE 2>&1
	displayResult $?

	echo "Detecting system architecture..."
	ARCH=`uname -m`
	displayMessage "System architecture: $ARCH"
	displayResult 0

	# We detect if the server is running 64bit OS and has 4Gb or more
	CUSTOM_OPTIONS=""
	if [ $ARCH == "x86_64" ]; then
		echo "Detecting system memory amount..."
		SYSTEM_MEMORY=`free -m | grep -i mem | awk '{print $2}'`
		displayMessage "System memory: $SYSTEM_MEMORY Mb"
		displayResult 0
		if [ $SYSTEM_MEMORY -gt 4000 ]; then
			CUSTOM_OPTIONS="--64bit_4GB"
		fi
	fi

	displayMessage "Building RPMs for Sangoma Wanpipe drivers"
	./Setup buildrpm --silent --split_rpms --protocol=TDM --with-linux=/usr/src/kernels/${KERNEL_VERSION}-${ARCH} --zaptel-path=/usr/src/dahdi-linux-${DAHDI_VERSION} ${CUSTOM_OPTIONS} >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Changing directory to /usr/src/redhat/RPMS/$ARCH"	
	cd /usr/src/redhat/RPMS/${ARCH} >> $LOG_FILE 2>&1
	displayResult $?

	displayMessage "Installing Sangoma Wanpipe RPMs"
	yum --nogpgcheck -y localinstall wanpipe*.rpm >> $LOG_FILE 2>&1
	displayResult $?

fi

echo ""
echo "Please access the A2Billing admin interface at the following URL:"
echo
echo "http://$SERVER_IP/billing/admin"
echo "User: root"
echo "Password: changepassword"
echo
echo -e "\E[1;32mA2Billing was successfully installed on your system, please reboot it to check everything is working properly"
tput sgr0
echo ""

exit 0
