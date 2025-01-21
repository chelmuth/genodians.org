#!/bin/sh

#SERVER=localhost:5556
#SERVER=genodians.org
SERVER=testing.genodians.org

# CONFDIR
#   private/key.pem         account private key
#   private/SERVER/key.pem  SERVER private key     - privkey.pem
#   SERVER/cert.pem         certificate for SERVER - fullchain.pem
CONFDIR="--confdir uacme.d"
CRYPTO="--type EC --bits 384"
STAGING="--staging"
VERBOSE="--verbose"

if [ "$1" = "uacme-issue" ]; then
	uacme ${FORCE} ${STAGING} ${VERBOSE} ${CONFDIR} ${CRYPTO} --hook $0 issue ${SERVER}
	exit $?
fi

if [ "$1" = "user-conf" ]; then
	if [ -z "$WEBDAV_USER" ] || [ -z "$WEBDAV_PASSWORD" ]; then
		echo "user-conf requires WEBDAV_USER and WEBDAV_PASSWORD environment variables set"
		exit 1
	fi
	echo $WEBDAV_USER:upload:$(echo -n $WEBDAV_USER:upload:$WEBDAV_PASSWORD | sha256sum | head -c 64)
	exit $?
fi

#
# uacme challenge hook script follows
#
# The hook not always executed accord. to the Let's encrypt FAQ.
#
# Once you successfully complete the challenges for a domain, the resulting
# authorization is cached for your account to use again later. Cached
# authorizations last for 30 days from the time of validation. If the
# certificate you requested has all of the necessary authorizations cached then
# validation will not happen again until the relevant cached authorizations
# expire.
#

if [ $# -ne 5 ]; then
	echo "Usage:"
	echo "  $(basename "$0") method type ident token auth   hook-script mode"
	echo "  $(basename "$0") uacme-issue                    issue new certificate"
	echo "  $(basename "$0") user-conf                      generate upload-user.conf contents"
	exit 85
fi

METHOD=$1
TYPE=$2
IDENT=$3
TOKEN=$4
AUTH=$5

if [ "$TYPE" != http-01 ]; then
	exit 1
fi

#echo "--- METHOD=${METHOD} TYPE=${TYPE} IDENT=${IDENT} TOKEN=${TOKEN} AUTH=${AUTH}"

WEBDAV_USER=user
WEBDAV_PASSWORD=pw
WEBDAV="curl --insecure --digest --user $WEBDAV_USER:$WEBDAV_PASSWORD"

case "$METHOD" in
	"begin")
		printf "%s" "${AUTH}" > TOKEN
		$WEBDAV --upload-file TOKEN https://${SERVER}/.well-known/acme-challenge/${TOKEN}
		exit $?
		;;

	"done")
		rm TOKEN
		$WEBDAV --request DELETE https://localhost:5556/.well-known/${TOKEN}
		$WEBDAV --upload-file uacme.d/${SERVER}/cert.pem https://${SERVER}/upload/cert/fullchain.pem
		exit $?
		;;

	"failed")
		rm TOKEN
		$WEBDAV --request DELETE https://localhost:5556/.well-known/${TOKEN}
		exit $?
		;;

	*)
		echo "$0: invalid method" 1>&2 
		exit 1
esac

#
# Notes
#
# openssl s_client -connect ${SERVER}:443 -servername ${SERVER} | openssl x509 -noout -dates
# openssl rsa  -in privkey.pem   -text -noout
# openssl x509 -in fullchain.pem -text -noout
# openssl req  -new -x509 -keyout privkey.pem -out fullchain.pem -days 365 -nodes
#
# uacme [--staging] --verbose --type EC --bits 384 --confdir $CONFDIR new [EMAIL]
# uacme [--staging] --verbose --type EC --bits 384 --confdir $CONFDIR update [EMAIL]
# uacme [--staging] --verbose --type EC --bits 384 --confdir $CONFDIR --hook ./uacme.sh issue ${SERVER}
# uacme [--staging] --verbose --type EC --bits 384 --confdir $CONFDIR revoke ${SERVER}
#
# curl --insecure --digest --user user:pw --upload-file TOKEN         https://${SERVER}/upload/acme-challenge/
# curl --insecure --digest --user user:pw --upload-file fullchain.pem https://${SERVER}/upload/cert/
# curl --insecure --digest --user user:pw --request DELETE            https://${SERVER}/upload/acme-challenge/TOKEN
#
# echo user:upload:$(echo -n user:upload:pw | sha256sum | head -c 64) > upload-user.conf
