#!/bin/bash 
#the function returns the username from the public key file name.  sed -e, that -e replaces string part.
get_key_username () {
  echo "$1" | sed -e 's/.*\///g' | sed -e 's/\.pub//g'
}

#Check pub keys available in S3 bucket
aws --region eu-west-1 s3api list-objects --bucket newbucket --prefix pub_keys/ --output text --query 'Contents[?Size>`0`].Key' | sed -e 'y/\t/\n/'|cut -c 10- >/etc/ansible/s3_keys_list
while read line; do
	USER_NAME="`get_key_username "$line"`"
	#only the input lines selected against an entire fixed string are out without given output since it is in -e silence mode.
	cut -d: -f1 /etc/passwd | grep -qx $USER_NAME
	#if no user in OS, add user, install key
	if [ $? -eq 1 ]; then
		#download playbooks
        #/usr/local/bin/aws s3 sync s3://sanoma-sandbox-bastion/bastion_playbooks/ /etc/ansible
		#download pub keys to /s3_pub_keys directory under /etc/ansible
		/usr/local/bin/aws s3 sync s3://newbucket/pub_keys/ /etc/ansible/s3_pub_keys
		# set USER_NAME to be in ansible var file user.yml, append user to key installed.
		sed -i 's/name:.*$/name: '"$USER_NAME"'/' /etc/ansible/users.yml
		ansible-playbook /etc/ansible/createusers.yml && echo "$line" >> /etc/ansible/keys_installed
	fi
done < /etc/ansible/s3_keys_list 


#remove user part
if [ -f /etc/ansible/keys_installed ]; then
	sort -uo /etc/ansible/keys_installed /etc/ansible/keys_installed
	sort -uo /etc/ansible/s3_keys_list /etc/ansible/s3_keys_list
	#save lines unique to S3_keys_list
	comm -13 /etc/ansible/s3_keys_list /etc/ansible/keys_installed| sed "s/\t//g" > /etc/ansible/keys_to_remove
	while read line; do
		USER_NAME="`get_key_username "$line"`" 
		#    /usr/sbin/userdel -r -f $USER_NAME
		# or use playbook to delete:
		sed -i 's/name:.*$/name: '"$USER_NAME"'/' /etc/ansible/removeusers.yml
		ansible-playbook /etc/ansible/removeusers.yml
	done < /etc/ansible/keys_to_remove
	cp /etc/ansible/s3_keys_list /etc/ansible/keys_installed
fi
