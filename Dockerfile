FROM lscr.io/linuxserver/chrome:latest

# Ensure Chrome starts with remote debugging enabled on all interfaces
ENV CHROME_CLI="--remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --no-sandbox"

# Install Node.js and the opencode browser CLI so the container provides the
# browsing CLI tools alongside Chrome. We install the CLI directly from the
# upstream GitHub repo to ensure the container has the latest tools.
RUN apt-get update && apt-get install -y curl ca-certificates gnupg git lsb-release \
	&& curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
	&& apt-get install -y nodejs build-essential \
	&& npm install -g git+https://github.com/different-ai/opencode-browser.git \
	&& apt-get remove -y build-essential gnupg lsb-release \
	&& apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 9222 3000 3001

CMD ["/init"]
