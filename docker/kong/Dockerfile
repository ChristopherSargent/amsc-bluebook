FROM kong:3.9

# Install the community OpenID Connect plugin and its dependencies.
# lua-resty-openidc transitively requires lua-resty-http and lua-resty-session.
# The plugin source: https://github.com/cuongntr/kong-openid-connect-plugin
USER root
RUN luarocks install lua-resty-http && \
    luarocks install lua-resty-session && \
    luarocks install lua-resty-openidc && \
    luarocks install kong-openid-connect

USER kong
