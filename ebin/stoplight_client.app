{application, stoplight_client, [
        {description, "Stoplight Client"},
        {vsn, "0.1"},
        {modules, [stoplight_client]},
        {env, [
          {port, 8648},
          {servers,[undefined]}
        ]},
        {registered, [stoplight_client]},
        {applications, [kernel, stdlib]},
        {mod, {stoplight_client, []}}
]}.
