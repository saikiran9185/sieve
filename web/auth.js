// Accounts for Sieve on the web.
//
// An account is optional and always will be. The library still lives in this browser and
// keeps working with the network off; signing in only adds backup and sync on top (sync
// itself arrives in a later step). So this module never blocks the app: it lays a sign-in
// screen over it on first visit, and "Use Sieve without an account" simply takes it away.
//
// Design follows the approved Figma frame "Sign in" (2:84): sky page, white card with an ink
// rule, Instrument Serif title, orange primary button.

const GUEST_KEY = 'sieve.guest';          // remembered choice to skip sign-in on this browser
const LAST_SYNC_KEY = 'sieve.lastSynced'; // updated whenever sync.js reports a finished sync

let client = null;
let session = null;
const listeners = new Set();

// Browser storage can throw (private windows, blocked site data), so every access is guarded.
const remember = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch {} },
  drop(k) { try { localStorage.removeItem(k); } catch {} },
};

export function user() { return session?.user || null; }
export function onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }
export function supabase() { return client; }

/// Starts accounts. Safe to call when the library or config is missing (offline first visit,
/// blocked script): the app then simply runs as it always has, without an account.
export async function start() {
  const cfg = window.SIEVE_SUPABASE;
  if (!window.supabase?.createClient || !cfg?.url) { renderAccountButton(); return; }

  client = window.supabase.createClient(cfg.url, cfg.publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' },
  });

  client.auth.onAuthStateChange((event, s) => {
    session = s;
    if (event === 'PASSWORD_RECOVERY') showScreen('newPassword');
    else if (s && event === 'SIGNED_IN') { remember.drop(GUEST_KEY); hideScreen(); }
    renderAccountButton();
    for (const fn of listeners) fn(user());
  });

  try {
    const { data } = await client.auth.getSession();
    session = data.session;
  } catch { session = null; } // offline: carry on as a guest for now

  renderAccountButton();
  const returningFromEmail = /[?&#](code|token_hash|type)=/.test(location.href);
  if (!session && !remember.get(GUEST_KEY) && !returningFromEmail) showScreen('login');
}

// ---------------------------------------------------------------- the sign-in screen

const COPY = {
  login: {
    title: 'Welcome back.',
    explain: 'Your review is on this computer. Signing in backs it up and brings it to your other devices.',
  },
  signup: {
    title: 'Make an account.',
    explain: 'Free. Your review stays on this computer as well; the account adds a backup and your other devices.',
  },
  magic: {
    title: 'Email me a link.',
    explain: 'No password needed. We send a link that signs you in on this browser.',
  },
  forgot: {
    title: 'Reset your password.',
    explain: 'Enter the email you signed up with and we will send a link to choose a new password.',
  },
  newPassword: {
    title: 'Choose a new password.',
    explain: 'At least 8 characters. You will stay signed in on this browser.',
  },
};

let overlay = null;

function showScreen(mode, note) {
  if (!overlay) {
    overlay = document.createElement('div');
    overlay.id = 'auth';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-labelledby', 'authTitle');
    document.body.appendChild(overlay);
  }
  overlay.innerHTML = '';
  overlay.hidden = false;

  const top = h('header', 'auth-top');
  top.appendChild(h('span', 'auth-logo', 'Sieve'));
  overlay.appendChild(top);

  const card = h('form', 'auth-card');
  card.noValidate = true;
  overlay.appendChild(card);

  if (mode === 'checkEmail') return renderCheckEmail(card, note);

  const c = COPY[mode];
  const title = h('h1', 'auth-title', c.title); title.id = 'authTitle';
  card.append(title, h('p', 'auth-explain', c.explain));

  const status = h('p', 'auth-status'); status.setAttribute('role', 'status'); status.hidden = true;

  const email = mode !== 'newPassword' ? field(card, 'Email', 'email', 'email', 'you@university.ac.in') : null;
  const pw = (mode === 'login' || mode === 'signup' || mode === 'newPassword')
    ? field(card, mode === 'login' ? 'Password' : 'New password', 'password',
            mode === 'login' ? 'current-password' : 'new-password', mode === 'login' ? '' : 'At least 8 characters')
    : null;

  const label = { login: 'Log in', signup: 'Create account', magic: 'Send the link',
                  forgot: 'Send reset link', newPassword: 'Save password' }[mode];
  const primary = h('button', 'auth-btn auth-primary', label); primary.type = 'submit';
  card.appendChild(primary);

  if (mode === 'login') {
    const alt = h('button', 'auth-btn', 'Email me a link instead'); alt.type = 'button';
    alt.onclick = () => showScreen('magic');
    card.appendChild(alt);
  }
  card.appendChild(status);

  const links = h('div', 'auth-links');
  if (mode === 'login') {
    links.append(link('Create account', () => showScreen('signup')),
                 link('Forgot password?', () => showScreen('forgot')));
  } else if (mode !== 'newPassword') {
    links.append(link('I have an account, log in', () => showScreen('login')));
  }
  if (links.childNodes.length) card.appendChild(links);

  if (mode !== 'newPassword') {
    const guest = link('Use Sieve without an account →', () => {
      remember.set(GUEST_KEY, '1');
      hideScreen();
    }, 'auth-guest');
    card.appendChild(guest);
  }

  card.onsubmit = async (e) => {
    e.preventDefault();
    const say = (msg, bad = false) => { status.hidden = !msg; status.textContent = msg || ''; status.classList.toggle('bad', bad); };
    const addr = email?.value.trim();
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(addr)) { say('That email does not look complete.', true); email.focus(); return; }
    if (pw && mode !== 'login' && pw.value.length < 8) { say('The password needs at least 8 characters.', true); pw.focus(); return; }
    if (pw && !pw.value) { say('Enter your password.', true); pw.focus(); return; }
    if (!navigator.onLine) { say('You are offline. Sieve still works without an account; sign in when you are back online.', true); return; }

    primary.disabled = true; say('One moment…');
    const back = location.origin + location.pathname;
    try {
      let res;
      if (mode === 'login') res = await client.auth.signInWithPassword({ email: addr, password: pw.value });
      if (mode === 'signup') res = await client.auth.signUp({ email: addr, password: pw.value, options: { emailRedirectTo: back } });
      if (mode === 'magic') res = await client.auth.signInWithOtp({ email: addr, options: { emailRedirectTo: back, shouldCreateUser: false } });
      if (mode === 'forgot') res = await client.auth.resetPasswordForEmail(addr, { redirectTo: back });
      if (mode === 'newPassword') res = await client.auth.updateUser({ password: pw.value });
      if (res?.error) throw res.error;

      if (mode === 'signup') {
        // With email confirmation on there is no session yet: the person must click the link.
        if (res.data.session) hideScreen(); else showScreen('checkEmail', { addr, why: 'confirm your account' });
      } else if (mode === 'magic') showScreen('checkEmail', { addr, why: 'sign in' });
      else if (mode === 'forgot') showScreen('checkEmail', { addr, why: 'choose a new password' });
      else hideScreen();
    } catch (err) {
      primary.disabled = false;
      say(plain(err), true);
    }
  };

  (email || pw)?.focus();
}

function renderCheckEmail(card, { addr, why }) {
  const title = h('h1', 'auth-title', 'Check your email.'); title.id = 'authTitle';
  card.append(title, h('p', 'auth-explain',
    `We sent a link to ${addr}. Open it on this device to ${why}. It can take a minute; look in spam if it does not arrive.`));
  const back = h('button', 'auth-btn', 'Back to log in'); back.type = 'button';
  back.onclick = () => showScreen('login');
  card.appendChild(back);
  card.appendChild(link('Use Sieve without an account →', () => { remember.set(GUEST_KEY, '1'); hideScreen(); }, 'auth-guest'));
}

function hideScreen() { if (overlay) overlay.hidden = true; }

/// Supabase's messages are written for developers; these are written for researchers.
function plain(err) {
  const m = String(err?.message || err || '').toLowerCase();
  if (m.includes('invalid login')) return 'That email and password do not match. Check both, or reset the password.';
  if (m.includes('email not confirmed')) return 'Confirm your email first: open the link we sent when you signed up.';
  if (m.includes('already registered') || m.includes('already been registered')) return 'There is already an account with this email. Log in instead.';
  if (m.includes('signups not allowed') || m.includes('user not found')) return 'There is no account with this email yet. Create one first.';
  if (m.includes('rate limit') || m.includes('too many')) return 'Too many emails sent in a short time. Wait a few minutes and try again.';
  if (m.includes('weak') || m.includes('password should')) return 'Choose a longer or less common password.';
  if (m.includes('failed to fetch') || m.includes('network')) return 'Could not reach the server. Check the connection; Sieve keeps working without an account.';
  return err?.message || 'Something went wrong. Try again in a moment.';
}

// ---------------------------------------------------------------- account button + menu

function renderAccountButton() {
  const btn = document.getElementById('accountBtn');
  if (!btn) return;
  const u = user();
  btn.innerHTML = '';
  btn.append(h('span', 'acct-name', u ? u.email : 'Not signed in'),
             h('span', 'meta', u ? 'Account' : client ? 'Sign in to back up' : 'Accounts unavailable offline'));
  btn.onclick = () => (u ? openAccountMenu() : client && showScreen('login'));
}

async function openAccountMenu() {
  const u = user();
  const modal = document.getElementById('modal'), body = document.getElementById('modalBody');
  body.innerHTML = '';
  body.appendChild(h('h2', null, 'Your account'));

  const rows = h('dl', 'acct-rows');
  const row = (k, v) => { rows.append(h('dt', null, k), h('dd', null, v)); return rows.lastChild; };
  row('Email', u.email);
  const used = row('Storage used', 'Checking…');
  const last = remember.get(LAST_SYNC_KEY);
  row('Last synced', last ? new Date(last).toLocaleString() : 'Not yet. Your work is saved in this browser and uploads on the next sync.');
  body.appendChild(rows);

  const actions = h('div', 'row');
  const close = h('button', 'quiet', 'Close');
  const out = h('button', null, 'Log out');
  actions.append(close, out);
  body.appendChild(actions);
  body.appendChild(h('p', 'hint', 'Logging out leaves your review in this browser. Nothing is deleted.'));

  close.onclick = () => modal.classList.add('hidden');
  out.onclick = async () => {
    out.disabled = true;
    await client.auth.signOut().catch(() => {});
    modal.classList.add('hidden');
    showScreen('login');
  };
  modal.classList.remove('hidden');

  used.textContent = await storageUsed(u.id);
}

/// Sum of this account's PDFs in the bucket, against the free plan's 1 GB.
async function storageUsed(uid) {
  try {
    const { data, error } = await client.storage.from('pdfs').list(uid, { limit: 1000 });
    if (error) throw error;
    const bytes = (data || []).reduce((n, f) => n + (f.metadata?.size || 0), 0);
    const mb = bytes / 1048576;
    return `${mb < 1 ? mb.toFixed(2) : mb.toFixed(0)} MB of 1 GB`;
  } catch { return 'Unavailable right now'; }
}

// ---------------------------------------------------------------- small DOM helpers

function h(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
}

function field(form, label, type, autocomplete, placeholder) {
  const id = 'auth-' + label.toLowerCase().replace(/\W+/g, '-');
  const l = h('label', 'auth-label', label); l.htmlFor = id;
  const i = h('input', 'auth-input'); i.id = id; i.type = type; i.autocomplete = autocomplete;
  if (placeholder) i.placeholder = placeholder;
  i.required = true;
  form.append(l, i);
  return i;
}

function link(text, onclick, cls = 'auth-link') {
  const b = h('button', cls, text);
  b.type = 'button';
  b.onclick = onclick;
  return b;
}


// Remember when the last sync finished, for the account sheet.
window.addEventListener('sieve:sync-status', (e) => { if (e.detail?.state === 'synced') remember.set(LAST_SYNC_KEY, new Date().toISOString()); });
