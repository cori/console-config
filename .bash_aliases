alias psa="ps -fAl|more"
alias lsa="ls -lAFtc --author --color|more"
alias apdir="/etc/apache2"
alias svnfind="find .|grep .svn"
wpgrep() {
	grep -irn $1 .|grep -v "wp-includes/js/*"
}
hcurl() {
        curl --url $1 -I
}
alias getwp="curl http://wordpress.org/latest.tar.gz | tar xvz"
