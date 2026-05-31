FROM lscr.io/linuxserver/chrome:latest

# Ensure Chrome starts with remote debugging enabled on all interfaces
ENV CHROME_CLI="--remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --no-sandbox"

EXPOSE 9222 3000 3001

CMD ["/init"]
