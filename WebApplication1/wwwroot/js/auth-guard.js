// Client-side guard to redirect unauthenticated users to /login.html
// Keeps login/register open. This is a lightweight protection for static pages
// while server-side APIs are protected via JWT and a global fallback policy.
(function () {
    try {
        const PUBLIC = ['/login.html', '/register.html', '/privacy.html', '/support.html', '/favicon.ico'];
        const path = (window.location.pathname || '/').toLowerCase();
        // root should behave like index
        const normalized = (path === '/' ? '/index.html' : path);
        if (PUBLIC.includes(normalized)) return; // public pages
        const token = localStorage.getItem('jwt');
        if (!token) {
            // redirect to login page if there is no token
            // preserve attempted location via query param for UX (optional)
            const target = encodeURIComponent(window.location.pathname + window.location.search);
            window.location.replace('/login.html' + (target ? '?returnUrl=' + target : ''));
        }
    } catch (e) {
        // fail-open in case of unexpected errors
        console.error('auth-guard error', e);
    }
})();
