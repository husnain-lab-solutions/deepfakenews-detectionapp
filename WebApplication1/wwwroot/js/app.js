const API_BASE = ""; // relative to same origin
const AUTH_KEY = "jwt";

function getToken() { return localStorage.getItem(AUTH_KEY) || ""; }
function setToken(t) { if (t) localStorage.setItem(AUTH_KEY, t); }
function clearToken() { localStorage.removeItem(AUTH_KEY); }

async function authFetch(url, opts = {}) {
    const headers = Object.assign({ 'Content-Type': 'application/json' }, opts.headers || {});
    const token = getToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const res = await fetch(url, { ...opts, headers });
    if (res.status === 401) throw new Error('Unauthorized');
    return res;
}

function updateNavAuth() {
    const token = getToken();
    const logged = !!token;
    document.querySelectorAll('[data-when="guest"]').forEach(e => e.style.display = logged ? 'none' : 'inline');
    document.querySelectorAll('[data-when="auth"]').forEach(e => e.style.display = logged ? 'inline' : 'none');
}

function getReturnUrl() {
    const m = location.search.match(/[?&]returnUrl=([^&]+)/i);
    return m ? decodeURIComponent(m[1]) : '';
}

async function handleRegister(e) {
    e.preventDefault();
    const email = document.getElementById('reg-email').value.trim();
    const password = document.getElementById('reg-password').value.trim();
    const res = await fetch('/api/auth/register', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
    });
    if (!res.ok) {
        const t = await res.json().catch(() => ({}));
        throw new Error((Array.isArray(t) ? t.join(', ') : t?.message) || 'Registration failed');
    }
    // Do not auto-login after registration; send user to login page.
    await res.json().catch(() => ({}));
    const ret = getReturnUrl();
    const q = ret ? ('?returnUrl=' + encodeURIComponent(ret)) : '';
    window.location.href = '/login.html' + q;
}

async function handleLogin(e) {
    e.preventDefault();
    const email = document.getElementById('login-email').value.trim();
    const password = document.getElementById('login-password').value.trim();
    const res = await fetch('/api/auth/login', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
    });
    if (!res.ok) throw new Error('Invalid credentials');
    const data = await res.json();
    // Accept either camelCase or PascalCase from backend
    setToken(data.token || data.Token);
    const ret = getReturnUrl();
    window.location.href = ret || '/predict.html';
}

async function handlePredictText(e) {
    e.preventDefault();
    const text = document.getElementById('text-input').value.trim();
    const out = document.getElementById('text-output');
    out.innerHTML = '<div class="note">Predicting...</div>';
    try {
        const res = await authFetch('/api/predict/text', {
            method: 'POST', body: JSON.stringify({ text })
        });
        const data = await res.json();
        const isFake = data.label === 'Fake';
        const pct = Math.round(Number(data.confidence) * 100);
        const cardHtml = `
                <div class="card result reveal">
                    <div style="display:flex;align-items:center;justify-content:space-between;gap:10px">
                        <div>
                            <span class="badge ${isFake ? 'danger' : 'success'}">${data.label}</span>
                            <span class="chip ${isFake ? 'danger' : 'success'}">${pct}% confidence</span>
                        </div>
                    </div>
                    <div class="progress mt-3"><div class="bar ${isFake ? 'danger' : 'success'}" style="width:${pct}%"></div></div>
                    <div class="note mt-2">Confidence is calibrated; treat low values cautiously.</div>
                </div>`;
        out.innerHTML = cardHtml;
        const last = document.getElementById('last-result'); if (last) last.innerHTML = cardHtml;
        addRecent({ kind: 'text', label: data.label, confidence: pct });
    } catch (err) {
        out.innerHTML = `<div class="alert error">${err.message || err}</div>`;
    }
}

async function handlePredictImage(e) {
    e.preventDefault();
    const file = document.getElementById('image-file').files[0];
    const out = document.getElementById('image-output');
    if (!file) { out.textContent = 'Choose an image first'; return; }
    out.innerHTML = '<div class="note">Uploading...</div>';
    try {
        const fd = new FormData();
        fd.append('file', file);
        const token = getToken();
        const res = await fetch('/api/predict/image', { method: 'POST', headers: token ? { 'Authorization': `Bearer ${token}` } : {}, body: fd });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        const isFake = data.label === 'Fake';
        const pct = Math.round(Number(data.confidence) * 100);
        const cardHtml = `
                <div class="card result reveal">
                    <div style="display:flex;align-items:center;justify-content:space-between;gap:10px">
                        <div>
                            <span class="badge ${isFake ? 'danger' : 'success'}">${data.label}</span>
                            <span class="chip ${isFake ? 'danger' : 'success'}">${pct}% confidence</span>
                        </div>
                    </div>
                    <div class="progress mt-3"><div class="bar ${isFake ? 'danger' : 'success'}" style="width:${pct}%"></div></div>
                    <div class="note mt-2">Confidence is calibrated; treat low values cautiously.</div>
                </div>`;
        out.innerHTML = cardHtml;
        const last = document.getElementById('last-result'); if (last) last.innerHTML = cardHtml;
        addRecent({ kind: 'image', label: data.label, confidence: pct });
    } catch (err) {
        out.innerHTML = `<div class="alert error">${err.message || err}</div>`;
    }
}

async function loadHistory() {
    const tbody = document.getElementById('history-tbody');
    if (!tbody) return;
    try {
        const res = await authFetch('/api/history');
        const items = await res.json();
        tbody.innerHTML = items.map(x => {
            const isFake = x.result === 'Fake';
            const pct = Math.round(Number(x.confidence) * 100);
            return `
            <tr>
                <td>${new Date(x.timestamp).toLocaleString()}</td>
                <td><span class="chip">${x.contentType}</span></td>
                <td><span class="badge ${isFake ? 'danger' : 'success'}">${x.result}</span></td>
                <td>
                    <div class="progress compact"><div class="bar ${isFake ? 'danger' : 'success'}" style="width:${pct}%"></div></div>
                    <span class="note">${pct}%</span>
                </td>
                <td title="${x.inputPathOrText || ''}">${(x.inputPathOrText || '').slice(0, 60)}</td>
            </tr>`;
        }).join('');
    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="5"><div class="alert error">${err.message || err}</div></td></tr>`;
    }
}

function bindPageHandlers() {
    updateNavAuth();
    const regForm = document.getElementById('register-form');
    if (regForm) regForm.addEventListener('submit', e => handleRegister(e).catch(err => showFormError('register-error', err)));
    const loginForm = document.getElementById('login-form');
    if (loginForm) loginForm.addEventListener('submit', e => handleLogin(e).catch(err => showFormError('login-error', err)));
    const textForm = document.getElementById('text-form');
    if (textForm) textForm.addEventListener('submit', handlePredictText);
    const imgForm = document.getElementById('image-form');
    if (imgForm) imgForm.addEventListener('submit', handlePredictImage);
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) logoutBtn.addEventListener('click', () => { clearToken(); updateNavAuth(); window.location.href = '/'; });
    if (document.getElementById('history-tbody')) loadHistory();

    // Reveal-on-scroll for elements marked with [data-reveal]
    const toReveal = document.querySelectorAll('[data-reveal]');
    if (toReveal.length) {
        const io = new IntersectionObserver(entries => {
            entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('reveal'); io.unobserve(e.target); } });
        }, { threshold: 0.08 });
        toReveal.forEach(el => io.observe(el));
    }

    // Render a professional, consistent footer (site-wide)
    renderFooter();
}

function renderFooter() {
    try {
        const root = document.querySelector('.footer .container');
        if (!root) return;
        root.innerHTML = `
            <div class="footer-grid">
                <div class="footer-brand">
                    <a class="brand" href="/"><img class="logo-img" src="/img/logo.svg" alt="Deepfake News Detector logo"/><span>Deepfake News Detector</span></a>
                    <p class="note">AI-powered screening for text and images with calibrated confidence and private history.</p>
                </div>
            </div>
            <div class="footer-meta">
                <div>© <span id="y"></span> Deepfake News Detector</div>
                <div class="note">
                    <a href="/privacy.html">Privacy Policy</a>
                    • <a href="/support.html">Contact Us</a>
                    • <strong>For academic use only</strong>
                </div>
            </div>
        `;
        const y = root.querySelector('#y'); if (y) y.textContent = new Date().getFullYear();
    } catch { }
}

// Simple in-memory recent list
const recent = [];
function addRecent(item) {
    recent.unshift({ ts: new Date(), ...item });
    if (recent.length > 10) recent.pop();
    const list = document.getElementById('recent-list');
    if (list) {
        list.innerHTML = recent.map(r => `
                    <div class="recent-item" style="display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border);padding:8px 0">
                        <span class="chip">${r.kind}</span>
                        <span class="badge ${r.label === 'Fake' ? 'danger' : 'success'}">${r.label}</span>
                        <span class="note">${r.confidence}%</span>
                    </div>
                `).join('');
    }
}

function showFormError(id, err) {
    const el = document.getElementById(id);
    if (el) el.innerHTML = `<div class="alert error">${err.message || err}</div>`;
}

document.addEventListener('DOMContentLoaded', bindPageHandlers);
