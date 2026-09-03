sudo tee /etc/apt/apt.conf.d/99proxy << EOF
Acquire::Http::Proxy "$APT_PROXY";
Acquire::Https::Proxy "$APT_PROXY";
EOF
