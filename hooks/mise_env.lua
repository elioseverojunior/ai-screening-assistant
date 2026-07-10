function PLUGIN:MiseEnv(ctx)
    -- Access configuration from mise.toml via ctx.options
    local api_url = ctx.options.api_url or "https://api.example.com"
    local debug = ctx.options.debug or false

    -- Return array of environment variables
    return {
        {
            key = "API_URL",
            value = api_url
        },
        {
            key = "DEBUG",
            value = tostring(debug)
        },
        {
            key = "SERVICE_TOKEN",
            value = get_token_from_somewhere()  -- Your custom logic
        }
    }
end