(function () {
  "use strict";

  var STORAGE_KEY = "tsh_seo_auth";
  var RING_LEN = 326.56;

  var loginView = document.getElementById("login-view");
  var appView = document.getElementById("app-view");
  var apiBaseInput = document.getElementById("api-base");
  var passwordInput = document.getElementById("password");
  var loginBtn = document.getElementById("login-btn");
  var loginError = document.getElementById("login-error");
  var loadError = document.getElementById("load-error");

  function loadSaved() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
    } catch (e) {
      return null;
    }
  }

  function saveAuth(apiBase, password) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ apiBase: apiBase, password: password }));
  }

  function clearAuth() {
    localStorage.removeItem(STORAGE_KEY);
  }

  function showLogin(msg) {
    appView.classList.add("hidden");
    loginView.classList.remove("hidden");
    if (msg) {
      loginError.textContent = msg;
      loginError.classList.remove("hidden");
    }
  }

  function showApp() {
    loginView.classList.add("hidden");
    loginError.classList.add("hidden");
    appView.classList.remove("hidden");
  }

  function apiFetch(path, auth, opts) {
    opts = opts || {};
    var init = {
      method: opts.method || "GET",
      headers: { Authorization: "Bearer " + auth.password },
    };
    return fetch(auth.apiBase.replace(/\/$/, "") + path, init).then(function (res) {
      if (res.status === 401) throw new Error("auth");
      if (!res.ok) throw new Error("HTTP " + res.status);
      return res.json();
    });
  }

  function fmtDate(iso) {
    if (!iso) return "Never";
    var d = new Date(iso);
    return d.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  }

  function fmtShortDate(str) {
    if (!str) return "";
    var p = str.split("-");
    return parseInt(p[1], 10) + "/" + parseInt(p[2], 10);
  }

  function setScoreRing(score) {
    var ring = document.getElementById("score-ring");
    var el = document.getElementById("health-score");
    el.textContent = score;
    var offset = RING_LEN - (RING_LEN * score) / 100;
    ring.style.strokeDashoffset = String(offset);
    if (score >= 80) ring.style.stroke = "#22c55e";
    else if (score >= 60) ring.style.stroke = "#fbbf24";
    else ring.style.stroke = "#f87171";
  }

  function renderOverview(data) {
    var snap = data.snapshot || {};
    var tech = snap.technical || {};
    var ps = snap.pageSpeed || {};
    var calls = snap.calls || {};

    document.getElementById("site-name").textContent = data.site.name;
    document.getElementById("site-url").textContent = data.site.domain;

    setScoreRing(data.healthScore || 0);

    var deltaEl = document.getElementById("score-delta");
    var d = data.scoreDelta || 0;
    if (d > 0) {
      deltaEl.textContent = "+" + d + " vs yesterday";
      deltaEl.className = "score-delta up";
    } else if (d < 0) {
      deltaEl.textContent = d + " vs yesterday";
      deltaEl.className = "score-delta down";
    } else {
      deltaEl.textContent = "No change vs yesterday";
      deltaEl.className = "score-delta flat";
    }

    document.getElementById("last-updated").textContent =
      "Updated " + fmtDate(data.lastUpdated);

    var metrics = [
      {
        label: "Response",
        value: tech.responseMs != null ? tech.responseMs + "ms" : "-",
        status: tech.responseMs < 2000 ? "good" : tech.responseMs < 4000 ? "warn" : "bad",
      },
      {
        label: "Mobile perf",
        value: ps.performance != null ? ps.performance : "N/A",
        status: ps.performance >= 80 ? "good" : ps.performance >= 50 ? "warn" : "bad",
      },
      {
        label: "Lighthouse SEO",
        value: ps.seo != null ? ps.seo : "N/A",
        status: ps.seo >= 90 ? "good" : ps.seo >= 70 ? "warn" : "bad",
      },
      {
        label: "Calls (7d)",
        value: calls.week != null ? calls.week : 0,
        status: "good",
      },
      {
        label: "Calls (all)",
        value: calls.total != null ? calls.total : 0,
        status: "good",
      },
      {
        label: "Integrations",
        value: countConnected(snap.integrations) + "/5",
        status: countConnected(snap.integrations) >= 3 ? "good" : "warn",
      },
    ];

    document.getElementById("metric-grid").innerHTML = metrics
      .map(function (m) {
        return (
          '<div class="metric status-' +
          m.status +
          '"><div class="metric-value">' +
          escapeHtml(String(m.value)) +
          '</div><div class="metric-label">' +
          escapeHtml(m.label) +
          "</div></div>"
        );
      })
      .join("");

    renderTrend(data.history || []);

    document.getElementById("leads-card").innerHTML =
      '<div class="card-row"><span>Inbound calls this week</span><span>' +
      (calls.week || 0) +
      '</span></div><div class="card-row"><span>Total tracked calls</span><span>' +
      (calls.total || 0) +
      '</span></div><div class="card-row"><span>Callback forms (7d)</span><span>' +
      (calls.formLeadsWeek || 0) +
      '</span></div><div class="card-row"><span>Phone link taps (7d)</span><span>' +
      (calls.phoneClicksWeek || 0) +
      "</span></div>";

    var auto = snap.automation || {};
    var pings = auto.pings || [];
    function pingRow(engine) {
      var p = pings.find(function (x) {
        return x.engine === engine;
      });
      var ok = p && p.ok;
      return (
        '<div class="card-row"><span>' +
        engine.charAt(0).toUpperCase() +
        engine.slice(1) +
        ' sitemap ping</span><span class="status-' +
        (ok ? "good" : "warn") +
        '">' +
        (p ? (ok ? "OK" : String(p.status || "fail")) : "pending") +
        "</span></div>"
      );
    }
    var idx = auto.indexNow || {};
    document.getElementById("automation-card").innerHTML =
      pingRow("google") +
      pingRow("bing") +
      '<div class="card-row"><span>IndexNow</span><span class="status-' +
      (idx.ok ? "good" : "warn") +
      '">' +
      (idx.ok ? "Submitted" : idx.status || "pending") +
      '</span></div><div class="card-row"><span>Last automation run</span><span>' +
      fmtDate(auto.at) +
      "</span></div>";
  }

  function countConnected(integrations) {
    if (!integrations) return 0;
    var n = 0;
    if (integrations.gsc) n++;
    if (integrations.ga4) n++;
    if (integrations.gbp) n++;
    if (integrations.serpapi) n++;
    if (integrations.pagespeed) n++;
    return n;
  }

  function renderTrend(history) {
    var el = document.getElementById("trend-chart");
    if (!history.length) {
      el.innerHTML = '<p class="empty-state">Trend builds after a few daily checks.</p>';
      return;
    }
    var max = 1;
    history.forEach(function (h) {
      if (h.health_score > max) max = h.health_score;
    });
    el.innerHTML = history
      .map(function (h) {
        var pct = Math.max(4, Math.round((h.health_score / max) * 100));
        return (
          '<div class="trend-bar-wrap"><div class="trend-bar" style="height:' +
          pct +
          '%" title="' +
          h.health_score +
          '"></div><span class="trend-label">' +
          fmtShortDate(h.snapshot_date) +
          "</span></div>"
        );
      })
      .join("");
  }

  function renderRankings(rankings, integrations) {
    var intro = document.getElementById("rankings-intro");
    var list = document.getElementById("rankings-list");

    if (!integrations || !integrations.serpapi) {
      intro.textContent =
        "Add SERPAPI_KEY to Cloudflare Worker secrets for daily rank tracking.";
      list.innerHTML =
        '<div class="empty-state">Rankings pending SerpAPI key.<br>Keywords are ready to track once connected.</div>';
      return;
    }

    if (!rankings.length) {
      list.innerHTML =
        '<div class="empty-state">No ranking data yet. Run refresh or wait for daily cron.</div>';
      return;
    }

    var byKw = {};
    rankings.forEach(function (r) {
      if (!byKw[r.keyword]) byKw[r.keyword] = [];
      byKw[r.keyword].push(r);
    });

    list.innerHTML = Object.keys(byKw)
      .map(function (kw) {
        var rows = byKw[kw]
          .sort(function (a, b) {
            if (a.is_competitor !== b.is_competitor) return a.is_competitor - b.is_competitor;
            var pa = a.position || 999;
            var pb = b.position || 999;
            return pa - pb;
          })
          .map(function (r) {
            var posClass = "none";
            var posText = "Not in top 20";
            if (r.position) {
              posText = "#" + r.position;
              posClass = r.position <= 3 ? "top3" : r.position <= 10 ? "mid" : "low";
            }
            return (
              '<div class="rank-row' +
              (r.is_competitor ? "" : " you") +
              '"><span>' +
              escapeHtml(r.target_label) +
              '</span><span class="rank-pos ' +
              posClass +
              '">' +
              posText +
              "</span></div>"
            );
          })
          .join("");
        return (
          '<div class="rank-group"><div class="rank-kw">' +
          escapeHtml(kw) +
          '</div>' +
          rows +
          "</div>"
        );
      })
      .join("");
  }

  function renderTechnical(snap) {
    var tech = snap.technical || {};
    var ps = snap.pageSpeed || {};

    var psHtml = "";
    if (ps && ps.performance != null) {
      psHtml =
        '<div class="card-row"><span>Performance</span><span>' +
        ps.performance +
        "/100</span></div>" +
        '<div class="card-row"><span>SEO score</span><span>' +
        (ps.seo || "-") +
        "/100</span></div>" +
        (ps.lcp
          ? '<div class="card-row"><span>LCP</span><span>' + escapeHtml(ps.lcp) + "</span></div>"
          : "") +
        (ps.cls
          ? '<div class="card-row"><span>CLS</span><span>' + escapeHtml(ps.cls) + "</span></div>"
          : "");
    } else {
      psHtml =
        '<p class="empty-state" style="padding:0">Add PAGESPEED_API_KEY for Lighthouse scores.</p>';
    }
    document.getElementById("pagespeed-card").innerHTML = psHtml;

    var checks = tech.checks || [];
    document.getElementById("check-list").innerHTML = checks
      .map(function (c) {
        return (
          '<li class="check-item"><span class="check-dot ' +
          c.status +
          '"></span><div class="check-body"><div class="check-label">' +
          escapeHtml(c.label) +
          '</div><div class="check-detail">' +
          escapeHtml(c.detail) +
          "</div></div></li>"
        );
      })
      .join("");
  }

  function renderSetup(snap) {
    var integ = snap.integrations || {};
    var items = [
      {
        name: "Google Business Profile",
        icon: "B",
        done: integ.gbp,
        detail: integ.gbp
          ? "Connected"
          : "Claim at business.google.com — use phone (567) 777-3443 and site URL. Send Place ID to enable dashboard tracking.",
      },
      {
        name: "Google Search Console",
        icon: "G",
        done: integ.gsc,
        detail: integ.gsc
          ? "Connected"
          : "Add property at search.google.com/search-console — paste gscDnsToken in seo-setup.json and redeploy for auto DNS verify",
      },
      {
        name: "Google Analytics 4",
        icon: "A",
        done: integ.ga4,
        detail: integ.ga4 ? "Measurement ID configured" : "Create GA4 property — paste ga4MeasurementId in seo-setup.json and redeploy (tag auto-injected)",
      },
      {
        name: "SerpAPI (rankings)",
        icon: "R",
        done: integ.serpapi,
        detail: integ.serpapi ? "Daily keyword tracking active" : "Set SERPAPI_KEY in Worker secrets",
      },
      {
        name: "PageSpeed API",
        icon: "P",
        done: integ.pagespeed,
        detail: integ.pagespeed ? "Core Web Vitals tracked" : "Set PAGESPEED_API_KEY in Worker secrets",
      },
    ];

    document.getElementById("setup-list").innerHTML = items
      .map(function (item) {
        return (
          '<div class="setup-item"><div class="setup-icon ' +
          (item.done ? "done" : "pending") +
          '">' +
          item.icon +
          '</div><div class="setup-body"><h3>' +
          escapeHtml(item.name) +
          "</h3><p>" +
          escapeHtml(item.detail) +
          "</p></div></div>"
        );
      })
      .join("");
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function renderAll(data) {
    renderOverview(data);
    renderRankings(data.rankings || [], data.snapshot && data.snapshot.integrations);
    renderTechnical(data.snapshot || {});
    renderSetup(data.snapshot || {});
  }

  function refresh(auth, manual) {
    loadError.classList.add("hidden");
    var btn = document.getElementById("refresh-btn");
    if (manual && btn) btn.textContent = "...";

    var chain = manual
      ? apiFetch("/api/seo/refresh", auth, { method: "POST" }).then(function () {
          return apiFetch("/api/seo/overview", auth);
        })
      : apiFetch("/api/seo/overview", auth);

    return chain
      .then(function (data) {
        renderAll(data);
      })
      .catch(function (err) {
        if (err.message === "auth") {
          clearAuth();
          showLogin("Session expired. Log in again.");
          return;
        }
        loadError.textContent = "Could not load SEO data. Try refresh.";
        loadError.classList.remove("hidden");
      })
      .finally(function () {
        if (btn) btn.textContent = "\u21BB";
      });
  }

  function doLogin() {
    var apiBase = apiBaseInput.value.trim();
    var password = passwordInput.value;
    loginError.classList.add("hidden");
    if (!apiBase || !password) {
      loginError.textContent = "Enter API URL and password.";
      loginError.classList.remove("hidden");
      return;
    }
    loginBtn.disabled = true;
    loginBtn.textContent = "Loading...";
    var auth = { apiBase: apiBase, password: password };
    apiFetch("/api/seo/overview", auth)
      .then(function (data) {
        saveAuth(apiBase, password);
        showApp();
        renderAll(data);
      })
      .catch(function (err) {
        clearAuth();
        if (err.message === "auth") {
          showLogin("Wrong password.");
          return;
        }
        loginError.textContent = "Could not reach API. (" + (err.message || "error") + ")";
        loginError.classList.remove("hidden");
      })
      .finally(function () {
        loginBtn.disabled = false;
        loginBtn.textContent = "Open Dashboard";
      });
  }

  document.querySelectorAll(".tab").forEach(function (tab) {
    tab.addEventListener("click", function () {
      var name = tab.getAttribute("data-tab");
      document.querySelectorAll(".tab").forEach(function (t) {
        t.classList.toggle("active", t === tab);
        t.setAttribute("aria-selected", t === tab ? "true" : "false");
      });
      document.querySelectorAll(".panel").forEach(function (p) {
        var on = p.id === "panel-" + name;
        p.classList.toggle("active", on);
        p.hidden = !on;
      });
    });
  });

  loginBtn.addEventListener("click", doLogin);
  passwordInput.addEventListener("keydown", function (e) {
    if (e.key === "Enter") doLogin();
  });

  document.getElementById("refresh-btn").addEventListener("click", function () {
    var auth = loadSaved();
    if (auth) refresh(auth, true);
  });

  document.getElementById("logout-btn").addEventListener("click", function () {
    clearAuth();
    showLogin();
  });

  if (window.location.pathname.indexOf("/seo") === 0) {
    apiBaseInput.value = window.location.origin;
  }

  var saved = loadSaved();
  if (saved) {
    showApp();
    refresh(saved, false);
  }
})();
