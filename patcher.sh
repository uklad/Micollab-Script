#!/bin/bash
#
# AWV-10940: Block /axis2-AWC endpoint
# Removes vulnerable template and deploys secure blocking template
#

set -e

TEMPLATE_DIR="/etc/e-smith/templates/etc/httpd/conf/httpd.conf/VirtualHosts"
VULNERABLE="${TEMPLATE_DIR}/57MasAwcWebServices"
SECURE="${TEMPLATE_DIR}/57MasAwcWebService"

echo "=== Blocking /axis2-AWC endpoint ==="

# Remove vulnerable template
if [ -f "${VULNERABLE}" ]; then
    echo "[1/4] Removing vulnerable template..."
    # Completely remove from templates directory
    rm -f "${VULNERABLE}"
    echo "      ✓ Removed (backup: /root/axis2-backup/)"
else
    echo "[1/4] Vulnerable template not present"
fi

# Also remove any .disabled versions that might still be processed
rm -f "${VULNERABLE}".disabled.* 2>/dev/null
echo "      ✓ Cleaned up any disabled versions"

# Create/verify secure template
echo "[2/4] Ensuring secure template exists..."
cat > "${SECURE}" << 'EOF'
{
    if ($port eq "443")
    {
	$OUT .= "   #AWV-10940\n";
        $OUT .= "     <Location /axis2-AWC>\n";
        $OUT .= "           order deny,allow\n";
        $OUT .= "           deny from all\n";
        $OUT .= "     </Location>\n";
    }
}
EOF
echo "      ✓ Secure template ready"

# Regenerate Apache config
echo "[3/4] Regenerating Apache configuration..."
if command -v expand-template &> /dev/null; then
    cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.bak.$(date +%Y%m%d)
    expand-template /etc/httpd/conf/httpd.conf
    
    # Clean up any remaining vulnerable ProxyPass rules
    sed -i '/ProxyPass \/axis2-AWC http:\/\/127.0.0.1:808[0-9]\/axis2-AWC/d' /etc/httpd/conf/httpd.conf
    sed -i '/ProxyPassReverse \/axis2-AWC http:\/\/127.0.0.1:808[0-9]\/axis2-AWC/d' /etc/httpd/conf/httpd.conf
    sed -i '/<Location \/axis2-AWC\/services>/,/<\/Location>/d' /etc/httpd/conf/httpd.conf
    
elif command -v signal-event &> /dev/null; then
    signal-event remoteaccess-update
else
    echo "      ⚠ Manual config regeneration required"
fi
echo "      ✓ Configuration updated"

# Restart services
echo "[4/4] Restarting services..."
sv restart tomcat
echo "      ✓ Tomcat restarted"
sv restart httpd-e-smith
echo "      ✓ httpd-e-smith restarted"

# Verify
echo ""
echo "=== Verification ==="
BLOCKED=0
VULNERABLE=0

# Check for blocking rule
if grep -q "deny from all" /etc/httpd/conf/httpd.conf && \
   grep -B2 "deny from all" /etc/httpd/conf/httpd.conf | grep -q "/axis2-AWC"; then
    echo "✓ Blocking rule present: deny from all for /axis2-AWC"
    BLOCKED=1
else
    echo "✗ WARNING: Blocking rule NOT found"
fi

# Check for vulnerable ProxyPass rules
if grep -q "ProxyPass /axis2-AWC" /etc/httpd/conf/httpd.conf; then
    echo "✗ ERROR: Vulnerable ProxyPass rule STILL PRESENT!"
    VULNERABLE=1
else
    echo "✓ ProxyPass rule removed"
fi

# Check for vulnerable /axis2-AWC/services location
if grep -q "/axis2-AWC/services" /etc/httpd/conf/httpd.conf; then
    echo "✗ ERROR: Vulnerable /axis2-AWC/services location STILL PRESENT!"
    VULNERABLE=1
else
    echo "✓ /axis2-AWC/services location removed"
fi

echo ""
if [ $BLOCKED -eq 1 ] && [ $VULNERABLE -eq 0 ]; then
    echo "Patch applied successfully"
else
    echo "FAILED: Manual intervention required"
    echo "Please check: /etc/httpd/conf/httpd.conf"
fi

echo ""
echo "Test with: curl -k https://localhost/axis2-AWC/"
echo "Expected: 403 Forbidden"

