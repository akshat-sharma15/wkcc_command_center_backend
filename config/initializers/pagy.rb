require "pagy/extras/headers"

Pagy::DEFAULT[:limit] = 25
Pagy::DEFAULT[:max_limit] = 100
Pagy::DEFAULT[:headers] = { page: "X-Page", limit: "X-Limit", count: "X-Count", pages: "X-Pages" }
