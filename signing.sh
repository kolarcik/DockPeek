# Společný výběr podpisového certifikátu pro build.sh a make-dmg.sh.
# DockPeek se podepisuje jen certifikáty týmu TEAM_ID (výchozí: s LUDĚK KOLARČÍK).
TEAM_ID="${TEAM_ID:-3ZN9TSG9S7}"

# find_identity "Developer ID Application" → SHA-1 certifikátu daného typu z týmu TEAM_ID (nebo nic)
find_identity() {
    local kind="$1" hash name
    while read -r hash name; do
        [[ "$name" == *"$kind"* ]] || continue
        if security find-certificate -a -Z -p 2>/dev/null \
            | awk -v h="$hash" 'BEGIN{RS="SHA-1 hash: "} index($0,h)==1 {sub(/^[^\n]*\n/,""); print; exit}' \
            | openssl x509 -noout -subject 2>/dev/null | grep -q "OU=$TEAM_ID"; then
            echo "$hash"
            return
        fi
    done < <(security find-identity -v -p codesigning | awk '/\)/ {h=$2; $1=$2=""; print h, $0}')
}
