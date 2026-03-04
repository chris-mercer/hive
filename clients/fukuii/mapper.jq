# Strip the config section from genesis JSON.
# Fukuii gets chain configuration from HOCON, not from genesis JSON.
# Keep alloc, gasLimit, difficulty, nonce, and other state fields.
del(.config)
