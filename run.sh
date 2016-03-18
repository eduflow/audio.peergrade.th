#!/usr/bin/env bash

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT
# or trap "killall" EXIT
# See: http://stackoverflow.com/questions/360201/how-do-i-kill-background-processes-jobs-when-my-shell-script-exits

killall darkice icecast mediatomb

echo "Hi, welcome to audio.peergrade.th!"
echo "Installing dependencies, please wait..."
[[ "$(brew ls --versions icecast                     )" == "" ]] && brew install icecast
[[ "$(brew ls --versions mediatomb                   )" == "" ]] && brew install mediatomb # jack darkice 
[[ "$(brew cask ls --versions soundflower 2>/dev/null)" == "" ]] && brew cask install soundflower
command -v darkice >/dev/null || {
  echo " - Compiling darkice-macosx, please wait..."
  brew install jack lame
  git clone git@github.com:rafael2k/darkice.git
  cd darkice/darkice/branches/darkice-macosx/
  aclocal
  autoheader
  automake --add-missing
  autoconf
  ./configure --with-jack --with-jack-prefix=/usr/local --with-core --with-lame --with-lame-prefix=/usr/local
  autoconf
  make install
  echo " - Done compiling and installing darkice-macosx."
}
echo "Done installing dependencies."

IP="$(ifconfig en1 | grep 'inet ' | cut -d' ' -f2)"
echo "Detected IP address: $IP"
HOSTNAME="$(hostname)"
echo "Detected hostname: $HOSTNAME"
STREAM_NAME="$HOSTNAME stream"
SERVER_NAME="Mediatomb - $HOSTNAME"

for f_conf_tmpl in *.tmpl; do
  f_conf="${f_conf_tmpl%.*}"
  if [[ ! -f "$f_conf" ]]; then
    echo "Making $f_conf from $f_conf_tmpl"
    sed "s/\$IP/$IP/g" "$f_conf_tmpl" | sed "s|\$PWD|$PWD|g" | sed "s/\$HOSTNAME/$HOSTNAME/g" | sed "s/\$SERVER_NAME/$SERVER_NAME/g" > "$f_conf"
  fi
done

# jackd -T -d coreaudio &
icecast -c config-icecast.xml &
sleep 2
darkice -c config-darkice.cfg &


# Start mediatomb, and let it initialize it's DB
mediatomb -c config-mediatomb.xml &
PID_MEDIATOMB=$!
sleep 4
kill $PID_MEDIATOMB
sleep 1

# Insert stream into mediatomb database
# sql_statement=<<<EOS
# INSERT OR REPLACE INTO mt_cds_object (id,ref_id,parent_id,object_type,upnp_class,dc_title,location,location_hash,metadata,auxdata,resources,update_id,mime_type,flags,track_number,service_id) VALUES (2,NULL,0,1,'object.container','Audio','V/Audio',3541114410,NULL,NULL,NULL,1,NULL,1,NULL,NULL); \
# INSERT OR REPLACE INTO mt_cds_object (id,ref_id,parent_id,object_type,upnp_class,dc_title,location,location_hash,metadata,auxdata,resources,update_id,mime_type,flags,track_number,service_id) VALUES (3,NULL,2,10,'object.item','Peergrade.audio','http://$IP:8000/stream.mp3',NULL,NULL,NULL,'0~protocolInfo=http-get%3A%2A%3Aaudio%2Fmpeg%3A%2A~~',0,'audio/mpeg',1,NULL,NULL);
# EOS

# http://stackoverflow.com/questions/418898/sqlite-upsert-not-insert-or-replace
sqlite3 mediatomb.db "INSERT OR REPLACE INTO mt_cds_object (id,ref_id,parent_id,object_type,upnp_class,dc_title,location,location_hash,metadata,auxdata,resources,update_id,mime_type,flags,track_number,service_id) VALUES (2,NULL,0,1,'object.container','Audio','V/Audio',3541114410,NULL,NULL,NULL,1,NULL,1,NULL,NULL)"
sqlite3 mediatomb.db "INSERT OR REPLACE INTO mt_cds_object (id,ref_id,parent_id,object_type,upnp_class,dc_title,location,location_hash,metadata,auxdata,resources,update_id,mime_type,flags,track_number,service_id) VALUES (3,NULL,2,10,'object.item','$STREAM_NAME','http://$IP:8000/stream.mp3',NULL,NULL,NULL,'0~protocolInfo=http-get%3A%2A%3Aaudio%2Fmpeg%3A%2A~~',0,'audio/mpeg',1,NULL,NULL)"

sleep 4

mediatomb -c config-mediatomb.xml &
sleep 4
echo "Broadcasting on UPNP as \"$SERVER_NAME\" with stream \"Audio/$STREAM_NAME\""
cat
