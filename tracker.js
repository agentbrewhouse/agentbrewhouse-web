/* ABH page view tracker -- non-blocking, no cookies, privacy-friendly */
(function () {
  var SUPA = 'https://vzoillfhilpvqxfkozbt.supabase.co';
  var KEY  = 'sb_publishable_W-aqyGXIqqaK53IMeRADTA_D5Ff34an';
  try {
    var p   = new URLSearchParams(location.search);
    var sid = sessionStorage.getItem('_abh_sid');
    if (!sid) { sid = Math.random().toString(36).slice(2); sessionStorage.setItem('_abh_sid', sid); }
    fetch(SUPA + '/rest/v1/page_views', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'apikey': KEY, 'Authorization': 'Bearer ' + KEY, 'Prefer': 'return=minimal' },
      body: JSON.stringify({
        page:         location.pathname,
        referrer:     document.referrer || null,
        utm_source:   p.get('utm_source'),
        utm_medium:   p.get('utm_medium'),
        utm_campaign: p.get('utm_campaign'),
        user_agent:   navigator.userAgent.slice(0, 200),
        session_id:   sid
      }),
      keepalive: true
    }).catch(function () {});
  } catch (e) {}
})();
