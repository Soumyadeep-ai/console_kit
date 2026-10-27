/* In-browser simulation of a ConsoleKit console session for the "Try it" page.
   Messages, ordering and menu rules mirror lib/console_kit (tenant_selector.rb, tenant_orchestrator.rb,
   tenant_configurator.rb, setup_ui.rb, the connection handlers and table_renderer.rb). Nothing here
   talks to a real backend. */
(function () {
  "use strict";

  var TENANTS = {
    acme: { shard: "shard_acme", partner_code: "acme", mongo_db: "acme_db", redis_db: 1, elasticsearch_prefix: "acme", environment: "production" },
    globex: { shard: "shard_globex", partner_code: "globex", mongo_db: "globex_db", redis_db: 2, elasticsearch_prefix: "globex", environment: "staging" },
    initech: { shard: "shard_initech", partner_code: "initech", mongo_db: "initech_db" },
    umbrella: { shard: "shard_umbrella", partner_code: "umbrella", mongo_db: "umbrella_db", redis_db: 4, elasticsearch_prefix: "umbrella" }
  };
  var REGISTERED_SHARDS = ["shard_acme", "shard_globex", "shard_initech"];
  var KEYS = Object.keys(TENANTS);
  var HANDLERS = ["sql", "mongo", "redis", "elasticsearch"];
  var DETAIL_LABELS = [["Partner", "partner_code"], ["Shard", "shard"], ["Mongo DB", "mongo_db"],
    ["Redis DB", "redis_db"], ["ES Prefix", "elasticsearch_prefix"], ["Environment", "environment"]];
  var MARKERS = { success: "[✓] ", error: "[✗] ", warning: "[!] " };
  var RETRY_LIMIT = 3;

  function Session(root) {
    this.root = root;
    this.log = root.querySelector(".ck-sim__log");
    this.form = root.querySelector(".ck-sim__form");
    this.label = root.querySelector(".ck-sim__label");
    this.input = root.querySelector(".ck-sim__input");
    this.restartButton = root.querySelector(".ck-sim__restart");
    this.history = [];
    this.historyIndex = 0;
    this.bind();
    this.boot();
  }

  Session.prototype.bind = function () {
    var self = this;
    this.form.addEventListener("submit", function (event) {
      event.preventDefault();
      self.submit(self.input.value);
    });
    this.input.addEventListener("keydown", function (event) {
      var key = event.key.toLowerCase();
      if (event.ctrlKey && key === "c") {
        event.preventDefault();
        self.interrupt();
      } else if (event.ctrlKey && key === "d" && !self.input.value && self.mode !== "irb") {
        /* End of input at the menu: $stdin.gets returns nil, which the selector treats as :abort. */
        event.preventDefault();
        self.echo("");
        self.finishMenu("abort");
      } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
        event.preventDefault();
        self.recall(event.key === "ArrowUp" ? -1 : 1);
      }
    });
    this.root.querySelector(".ck-sim__screen").addEventListener("click", function () {
      if (!window.getSelection().toString()) self.input.focus();
    });
    this.restartButton.addEventListener("click", function () { self.boot(); self.input.focus(); });
  };

  /* Output */

  Session.prototype.line = function (parts) {
    var row = document.createElement("div");
    row.className = "ck-sim__line";
    parts.forEach(function (part) {
      var span = document.createElement("span");
      if (part[1]) span.className = part[1];
      span.textContent = part[0];
      row.appendChild(span);
    });
    this.log.appendChild(row);
    this.log.scrollTop = this.log.scrollHeight;
  };

  Session.prototype.say = function (type, text) {
    var colour = { success: "ck-ok", error: "ck-err", warning: "ck-warn", header: "ck-h", prompt: "ck-p", trace: "ck-k" }[type];
    if (type === "header") {
      this.line([["[ConsoleKit] ", colour]]);
      this.line([["--- " + text + " ---", colour]]);
      return;
    }
    var marker = MARKERS[type] || "";
    if (colour) this.line([["[ConsoleKit] " + marker + text, colour]]);
    else this.line([["[ConsoleKit] ", "ck-k"], [text]]);
  };

  Session.prototype.plain = function (text, cls) { this.line([[text, cls]]); };
  Session.prototype.result = function (text) { this.plain("=> " + text); };

  /* Prompt */

  Session.prototype.setPrompt = function (mode) {
    this.mode = mode;
    var ended = mode === "ended";
    this.form.hidden = ended;
    this.restartButton.hidden = !ended;
    if (mode === "menu-boot" || mode === "menu-switch") {
      this.label.className = "ck-sim__label ck-p";
      this.label.textContent = "[ConsoleKit] Selection (number or name) [1]: ";
    } else if (mode === "irb") {
      var tenant = this.current ? "[" + this.current + "]" : "[no-tenant]";
      this.label.className = "ck-sim__label";
      this.label.innerHTML = "";
      var tag = document.createElement("span");
      tag.className = "ck-tenant";
      tag.textContent = tenant;
      this.label.appendChild(tag);
      this.label.appendChild(document.createTextNode(" main:" + String(this.count).padStart(3, "0") + "> "));
    }
  };

  Session.prototype.echo = function (value) {
    var promptText = this.label.textContent;
    if (this.mode === "irb") {
      var tenant = this.current ? "[" + this.current + "]" : "[no-tenant]";
      this.line([[tenant, "ck-tenant"], [promptText.slice(tenant.length)], [value, "ck-in"]]);
    } else {
      this.line([[promptText, "ck-p"], [value, "ck-in"]]);
    }
  };

  Session.prototype.submit = function (raw) {
    this.input.value = "";
    this.echo(raw);
    if (raw.trim()) { this.history.push(raw); }
    this.historyIndex = this.history.length;
    if (this.mode === "irb") this.evaluate(raw.trim());
    else this.answerMenu(raw);
  };

  Session.prototype.recall = function (step) {
    if (!this.history.length) return;
    this.historyIndex = Math.min(this.history.length, Math.max(0, this.historyIndex + step));
    this.input.value = this.history[this.historyIndex] || "";
  };

  Session.prototype.interrupt = function () {
    this.echo("^C");
    if (this.mode === "irb") return;
    this.finishMenu("abort");
  };

  /* Boot: TenantOrchestrator.run */

  Session.prototype.boot = function () {
    this.log.innerHTML = "";
    this.current = null;
    this.count = 1;
    this.backends = { shard: null, mongo_db: null, redis_db: 0, elasticsearch_prefix: null };
    this.plain("$ bin/rails console", "ck-k");
    this.showMenu("menu-boot");
  };

  Session.prototype.showMenu = function (mode) {
    this.attempts = 0;
    this.say("header", "Multiple tenants detected. Please choose one:");
    this.plain("  0. Skip (load without tenant configuration)");
    KEYS.forEach(function (key, index) {
      this.plain("  " + (index + 1) + ". " + key + " (partner: " + TENANTS[key].partner_code + ")");
    }, this);
    this.setPrompt(mode);
  };

  /* TenantSelector#parse_user_selection */
  Session.prototype.parse = function (raw) {
    var input = raw.trim() || "1";
    if (["exit", "quit"].indexOf(input.toLowerCase()) !== -1) return "exit";
    if (!/^\d+$/.test(input)) {
      var match = KEYS.filter(function (key) { return key.toLowerCase() === input.toLowerCase(); })[0];
      if (match) return match;
      this.say("warning", "Invalid selection: '" + input + "'. Please enter a number or tenant name.");
      return null;
    }
    var index = parseInt(input, 10);
    if (index < 0 || index > KEYS.length) {
      this.say("warning", "Selection must be between 0 and " + KEYS.length + ".");
      return null;
    }
    return index === 0 ? "none" : KEYS[index - 1];
  };

  Session.prototype.answerMenu = function (raw) {
    var choice = this.parse(raw);
    if (choice === null) {
      this.attempts += 1;
      if (this.attempts < RETRY_LIMIT) { this.showMenuAgain(); return; }
      this.finishMenu(null);
      return;
    }
    this.finishMenu(choice);
  };

  Session.prototype.showMenuAgain = function () {
    var attempts = this.attempts;
    this.showMenu(this.mode);
    this.attempts = attempts;
  };

  Session.prototype.finishMenu = function (choice) {
    if (this.mode === "menu-boot") this.finishBoot(choice);
    else this.finishReset(choice);
  };

  Session.prototype.finishBoot = function (choice) {
    if (choice === "exit" || choice === "abort") {
      this.say("info", "Exiting console...");
      this.setPrompt("ended");
      return;
    }
    if (choice === "none") this.say("info", "No tenant selected. Loading without tenant configuration.");
    else if (choice === null) this.say("error", "Tenant selection failed. Loading without tenant configuration.");
    else this.configure(choice);
    this.setPrompt("irb");
  };

  /* TenantOrchestrator#perform_reset, used by the switch_tenant helper */
  Session.prototype.finishReset = function (choice) {
    if (choice === "abort" || choice === null) this.say("warning", "Tenant switch cancelled.");
    else if (choice === this.current) this.say("info", "Already using tenant: " + choice + ". No changes made.");
    else if (choice === "exit" || choice === "none") this.clearTenant();
    else this.configure(choice);
    this.result("main");
    this.count += 1;
    this.setPrompt("irb");
  };

  Session.prototype.clearTenant = function () {
    if (this.current) {
      this.say("warning", "Resetting tenant: " + this.current);
      this.connect({});
      this.say("info", "Tenant context has been cleared.");
    }
    this.current = null;
    this.say("info", "No tenant selected. Loading without tenant configuration.");
  };

  /* TenantSwitch: validate and prepare (nothing changes yet), then connect each handler in order */

  /* `inspected` is how Ruby would #inspect the key: :acme for a Symbol, "acme" for a String.
     The demo's tenant keys are Symbols, so a String key is never found. */
  Session.prototype.prepareError = function (key, inspected) {
    if (!TENANTS[key] || (inspected && inspected.charAt(0) === "\"")) {
      return { cls: "ConsoleKit::TenantNotFoundError", missing: true,
        message: "No configuration found for tenant: " + (inspected || ":" + key) + ". Configured tenants: " +
          KEYS.map(function (k) { return ":" + k; }).join(", ") + "." };
    }
    var shard = TENANTS[key].shard;
    if (REGISTERED_SHARDS.indexOf(shard) === -1) {
      return { cls: "ConsoleKit::ConfigurationError",
        message: "ConsoleKit: SQL shard :" + shard + " is not a registered shard or database configuration." };
    }
    return null;
  };

  Session.prototype.connect = function (constants) {
    var shard = constants.shard || null;
    this.say("info", (shard ? "Establishing SQL connection to shard: " + shard : "Resetting SQL connection to default") + " via ApplicationRecord");
    var db = constants.redis_db || 0;
    if (db !== this.backends.redis_db) {
      this.say("info", db === 0 ? "Resetting Redis connection to default" : "Switching to Redis DB: " + db);
    }
    var prefix = constants.elasticsearch_prefix || null;
    this.say("info", prefix ? "Setting Elasticsearch index prefix: " + prefix : "Resetting Elasticsearch index prefix to default");
    this.backends = { shard: shard, mongo_db: constants.mongo_db || null, redis_db: db, elasticsearch_prefix: prefix };
  };

  /* TenantOrchestrator#configure: TenantConfigurator prints failures instead of raising */
  Session.prototype.configure = function (key) {
    var error = this.prepareError(key);
    if (error) {
      if (error.missing) this.say("error", "No configuration found for tenant: " + key);
      else this.say("error", "Failed to configure tenant '" + key + "': " + error.message);
      return;
    }
    if (key !== this.current) this.connect(TENANTS[key]);
    this.current = key;
    this.banner(key);
  };

  Session.prototype.banner = function (key) {
    this.say("success", "Tenant initialized: " + key);
    var env = (TENANTS[key].environment || "").toLowerCase();
    if (env === "production") this.say("error", "!!! CAUTION: YOU ARE IN PRODUCTION ENVIRONMENT !!!");
    if (env === "staging") this.say("warning", "CAUTION: You are in staging environment.");
    this.say("info", "Active connections: SQL, MongoDB, Redis, Elasticsearch");
  };

  /* IRB */

  Session.prototype.raise = function (cls, message) {
    this.plain("(irb):" + this.count + ":in '<main>': " + message + " (" + cls + ")", "ck-err");
  };

  Session.prototype.stateInspect = function () {
    return "#<ConsoleKit::TenantState :" + this.current + " backends=[:" + HANDLERS.join(", :") + "]>";
  };

  Session.prototype.evaluate = function (code) {
    if (!code) { this.setPrompt("irb"); return; }
    var programmatic = code.match(/^ConsoleKit\.switch_tenant\(\s*(:\w+|"[^"]*"|'[^']*')\s*\)$/);
    var dashboard = code.match(/^dashboard(?:\(\s*level:\s*:(basic|full)\s*\))?$/);

    if (code === "exit" || code === "quit") { this.setPrompt("ended"); return; }
    if (code === "switch_tenant") { this.showMenu("menu-switch"); return; }

    if (code === "help") {
      this.plain("This demo understands:", "ck-k");
      ["switch_tenant", "tenant_info", "tenants", "dashboard", "dashboard(level: :full)",
        "ConsoleKit.current_tenant", "ConsoleKit.switch_tenant(:globex)", "ConsoleKit.verify_tenant!", "exit"]
        .forEach(function (cmd) { this.plain("  " + cmd, "ck-k"); }, this);
      this.result("nil");
    } else if (code === "tenants") {
      this.say("header", "Available Tenants");
      KEYS.forEach(function (key) { this.plain("  " + key); }, this);
      this.result("[:" + KEYS.join(", :") + "]");
    } else if (code === "tenant_info") {
      this.tenantInfo();
      this.result("nil");
    } else if (dashboard) {
      this.dashboard(dashboard[1] || "basic");
      this.result("main");
    } else if (code === "ConsoleKit.current_tenant") {
      this.result(this.current ? ":" + this.current : "nil");
    } else if (code === "ConsoleKit.verify_tenant!") {
      if (this.current) this.result(this.stateInspect());
      else this.raise("ConsoleKit::ConfigurationError", "No tenant is currently configured.");
    } else if (programmatic) {
      this.programmaticSwitch(programmatic[1]);
    } else {
      /* Ruby names the first undefined identifier: the bare argument in switch_tenant(acme). */
      var bareArgument = code.match(/^ConsoleKit\.switch_tenant\(\s*([a-z_]\w*)\s*\)$/);
      var word = bareArgument ? bareArgument[1] : code.split(/[\s.(]/)[0];
      this.raise("NameError", "undefined local variable or method '" + word + "' for main");
      this.plain("Simulation: type help for the commands this demo understands.", "ck-k");
    }
    this.count += 1;
    this.setPrompt("irb");
  };

  /* ConsoleKit.switch_tenant: raises, always runs the full transaction, prints no banner */
  Session.prototype.programmaticSwitch = function (literal) {
    var key = literal.replace(/^:|^["']|["']$/g, "");
    var inspected = literal.charAt(0) === ":" ? literal : "\"" + key + "\"";
    var error = this.prepareError(key, inspected);
    if (error) { this.raise(error.cls, error.message); return; }
    this.connect(TENANTS[key]);
    this.current = key;
    this.result(this.stateInspect());
  };

  Session.prototype.tenantInfo = function () {
    if (!this.current) { this.say("warning", "No tenant is currently configured."); return; }
    var constants = TENANTS[this.current];
    this.say("header", "Tenant: " + this.current);
    DETAIL_LABELS.forEach(function (pair) {
      if (pair[1] in constants) this.say("info", "  " + pair[0].padEnd(13) + constants[pair[1]]);
    }, this);
  };

  /* Connections::Dashboard + TableRenderer */
  Session.prototype.dashboard = function (level) {
    var b = this.backends;
    var full = level === "full";
    var rows = full ? [
      ["SQL", "1.1ms", { adapter: "PostgreSQL", pool_size: 5, version: "PostgreSQL 16.4" }],
      ["MongoDB", "2.3ms", { database: b.mongo_db || "app_development", version: "7.0.14" }],
      ["Redis", "0.4ms", { db: b.redis_db, version: "7.2.5", memory: "1.21M" }],
      ["Elasticsearch", "3.8ms", { prefix: b.elasticsearch_prefix, cluster: "docker-cluster", health: "green" }]
    ] : [
      ["SQL", null, { adapter: "postgresql", pool_size: 5, config: "primary", shard: b.shard || "default" }],
      ["MongoDB", null, { database: b.mongo_db || "app_development" }],
      ["Redis", null, { db: b.redis_db, isolation: "scoped" }],
      ["Elasticsearch", null, { prefix: b.elasticsearch_prefix, isolation: "process_global" }]
    ];
    var cells = rows.map(function (row) {
      var details = Object.keys(row[2]).filter(function (k) { return row[2][k] !== null; })
        .map(function (k) { return k + ": " + row[2][k]; }).join(", ");
      return [row[0], "✓ Connected", row[1] || "—", details];
    });
    this.say("header", "Connection Dashboard");
    renderTable(["Service", "Status", "Latency", "Details"], cells).forEach(function (text) { this.plain(text); }, this);
  };

  function renderTable(headers, rows) {
    var all = [headers].concat(rows);
    var widths = headers.map(function (_, i) {
      return Math.max.apply(null, all.map(function (row) { return Array.from(row[i]).length; }));
    });
    function rule(corners) {
      return corners[0] + widths.map(function (w) { return "─".repeat(w + 2); }).join(corners[1]) + corners[2];
    }
    function line(cells) {
      return "│" + cells.map(function (cell, i) {
        return " " + cell + " ".repeat(widths[i] - Array.from(cell).length) + " ";
      }).join("│") + "│";
    }
    return [rule("┌┬┐"), line(headers), rule("├┼┤")].concat(rows.map(line), [rule("└┴┘")]);
  }

  document.querySelectorAll("[data-ck-sim]").forEach(function (root) { new Session(root); });
})();
