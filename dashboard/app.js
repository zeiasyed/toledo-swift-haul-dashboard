(function () {
  "use strict";

  var STORAGE_KEY = "tsh_dashboard_auth";
  var loginView = document.getElementById("login-view");
  var appView = document.getElementById("app-view");
  var apiBaseInput = document.getElementById("api-base");
  var passwordInput = document.getElementById("password");
  var loginBtn = document.getElementById("login-btn");
  var loginError = document.getElementById("login-error");
  var statsEl = document.getElementById("stats");
  var callList = document.getElementById("call-list");
  var emptyMsg = document.getElementById("empty-msg");
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

  function fmtTime(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return d.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  }

  function fmtPhone(num) {
    if (!num) return "Unknown";
    var d = String(num).replace(/\D/g, "");
    if (d.length === 11 && d[0] === "1") d = d.slice(1);
    if (d.length === 10) {
      return "(" + d.slice(0, 3) + ") " + d.slice(3, 6) + "-" + d.slice(6);
    }
    return num;
  }

  function fmtDuration(sec) {
    sec = parseInt(sec, 10) || 0;
    if (!sec) return "0s";
    if (sec < 60) return sec + "s";
    return Math.floor(sec / 60) + "m " + (sec % 60) + "s";
  }

  function apiFetch(path, auth) {
    return fetch(auth.apiBase.replace(/\/$/, "") + path, {
      headers: { Authorization: "Bearer " + auth.password },
    }).then(function (res) {
      if (res.status === 401) throw new Error("auth");
      if (!res.ok) throw new Error("HTTP " + res.status);
      return res.json();
    });
  }

  function renderStats(data) {
    var items = [
      { label: "Today", value: data.today },
      { label: "7 days", value: data.week },
      { label: "All time", value: data.total },
      { label: "Voicemails", value: data.voicemails },
      { label: "Avg duration", value: fmtDuration(data.avgDuration) },
    ];
    statsEl.innerHTML = items
      .map(function (item) {
        return (
          '<div class="stat"><div class="stat-value">' +
          item.value +
          '</div><div class="stat-label">' +
          item.label +
          "</div></div>"
        );
      })
      .join("");
  }

  function renderCalls(calls) {
    callList.innerHTML = "";
    if (!calls.length) {
      emptyMsg.classList.remove("hidden");
      return;
    }
    emptyMsg.classList.add("hidden");

    calls.forEach(function (call) {
      var card = document.createElement("article");
      card.className = "call-card";

      var statusClass = (call.status || "unknown").replace(/\s+/g, "-");
      var html =
        '<div class="call-top">' +
        '<span class="call-from">' +
        fmtPhone(call.from_number) +
        "</span>" +
        '<span class="call-time">' +
        fmtTime(call.created_at) +
        "</span></div>" +
        '<div class="call-meta">' +
        '<span class="badge ' +
        statusClass +
        '">' +
        (call.status || "unknown") +
        "</span>" +
        '<span class="badge">' +
        fmtDuration(call.duration) +
        "</span></div>";

      if (call.transcription) {
        html += '<p class="call-transcript">' + escapeHtml(call.transcription) + "</p>";
      }
      if (call.recording_url) {
        html +=
          '<div class="call-actions"><a href="' +
          escapeHtml(call.recording_url) +
          '" target="_blank" rel="noopener">Play voicemail</a></div>";
      }

      card.innerHTML = html;
      callList.appendChild(card);
    });
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function refresh(auth) {
    loadError.classList.add("hidden");
    Promise.all([apiFetch("/api/stats", auth), apiFetch("/api/calls?limit=50", auth)])
      .then(function (results) {
        renderStats(results[0]);
        renderCalls(results[1].calls || []);
      })
      .catch(function (err) {
        if (err.message === "auth") {
          clearAuth();
          showLogin("Wrong password or API URL.");
          return;
        }
        loadError.textContent = "Could not load data. Check API URL and try again.";
        loadError.classList.remove("hidden");
      });
  }

  loginBtn.addEventListener("click", function () {
    var apiBase = apiBaseInput.value.trim();
    var password = passwordInput.value;
    if (!apiBase || !password) {
      loginError.textContent = "Enter API URL and password.";
      loginError.classList.remove("hidden");
      return;
    }
    var auth = { apiBase: apiBase, password: password };
    apiFetch("/api/stats", auth)
      .then(function () {
        saveAuth(apiBase, password);
        showApp();
        refresh(auth);
      })
      .catch(function (err) {
        if (err.message === "auth") {
          clearAuth();
          showLogin("Wrong password or API URL.");
          return;
        }
        loginError.textContent =
          "Could not reach API. Check URL and try again. (" + (err.message || "network error") + ")";
        loginError.classList.remove("hidden");
      });
  });

  document.getElementById("refresh-btn").addEventListener("click", function () {
    var auth = loadSaved();
    if (auth) refresh(auth);
  });

  document.getElementById("logout-btn").addEventListener("click", function () {
    clearAuth();
    passwordInput.value = "";
    showLogin();
  });

  var saved = loadSaved();
  if (saved && saved.apiBase) {
    apiBaseInput.value = saved.apiBase;
    passwordInput.value = saved.password || "";
    showApp();
    refresh(saved);
  }
})();
