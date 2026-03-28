import { LoginCredential } from '../../services/auth/LoginCredentialStore';

const USERNAME_SELECTORS: string[] = [
  'input[name="login"]',
  'input[name="username"]',
  'input[name="email"]',
  'input[type="email"]',
  'input#login-account-name',
  'input.autocomplete'
];

const PASSWORD_SELECTORS: string[] = [
  'input[name="password"]',
  'input[type="password"]'
];

function buildSelectorArrayLiteral(selectors: string[]): string {
  const items: string[] = [];
  for (let i = 0; i < selectors.length; i++) {
    items.push(JSON.stringify(selectors[i]));
  }
  return `[${items.join(', ')}]`;
}

export class LoginAutoFillUtils {
  private static readonly USERNAME_SELECTOR_SCRIPT: string = buildSelectorArrayLiteral(USERNAME_SELECTORS);
  private static readonly PASSWORD_SELECTOR_SCRIPT: string = buildSelectorArrayLiteral(PASSWORD_SELECTORS);

  static buildCredentialTrackingScript(): string {
    return `(function() {
      try {
        if (!location || !location.pathname || location.pathname.indexOf('/login') < 0) {
          return;
        }
        if (window.__HarmonyDoCredentialTrackerInstalled === true) {
          return;
        }
        window.__HarmonyDoCredentialTrackerInstalled = true;
        var usernameSelectors = ${LoginAutoFillUtils.USERNAME_SELECTOR_SCRIPT};
        var passwordSelectors = ${LoginAutoFillUtils.PASSWORD_SELECTOR_SCRIPT};
        function pick(selectors) {
          for (var i = 0; i < selectors.length; i++) {
            var node = document.querySelector(selectors[i]);
            if (node) {
              return node;
            }
          }
          return null;
        }
        function ensureDraft() {
          if (!window.__HarmonyDoLoginCredentialDraft || typeof window.__HarmonyDoLoginCredentialDraft !== 'object') {
            window.__HarmonyDoLoginCredentialDraft = { username: '', password: '' };
          }
          return window.__HarmonyDoLoginCredentialDraft;
        }
        function syncDraft() {
          var draft = ensureDraft();
          var usernameInput = pick(usernameSelectors);
          var passwordInput = pick(passwordSelectors);
          draft.username = usernameInput && typeof usernameInput.value === 'string'
            ? usernameInput.value
            : (draft.username || '');
          draft.password = passwordInput && typeof passwordInput.value === 'string'
            ? passwordInput.value
            : (draft.password || '');
        }
        function bindInput(input) {
          if (!input || input.__HarmonyDoCredentialBound === true) {
            return;
          }
          input.__HarmonyDoCredentialBound = true;
          input.addEventListener('input', syncDraft);
          input.addEventListener('change', syncDraft);
          input.addEventListener('blur', syncDraft);
        }
        function bindOnce() {
          var usernameInput = pick(usernameSelectors);
          var passwordInput = pick(passwordSelectors);
          if (!usernameInput || !passwordInput) {
            return false;
          }
          bindInput(usernameInput);
          bindInput(passwordInput);
          syncDraft();
          return true;
        }
        var attempts = 0;
        var timer = setInterval(function() {
          attempts = attempts + 1;
          if (bindOnce() || attempts > 40) {
            clearInterval(timer);
          }
        }, 250);
        bindOnce();
        document.addEventListener('DOMContentLoaded', function() {
          bindOnce();
        });
      } catch (_) {
      }
    })();`;
  }

  static buildFillCredentialScript(credential: LoginCredential): string {
    const username: string = credential.username !== undefined && credential.username !== null ? credential.username : '';
    const password: string = credential.password !== undefined && credential.password !== null ? credential.password : '';
    return `(function() {
      try {
        if (!location || !location.pathname || location.pathname.indexOf('/login') < 0) {
          return JSON.stringify({ filled: false });
        }
        var usernameSelectors = ${LoginAutoFillUtils.USERNAME_SELECTOR_SCRIPT};
        var passwordSelectors = ${LoginAutoFillUtils.PASSWORD_SELECTOR_SCRIPT};
        function pick(selectors) {
          for (var i = 0; i < selectors.length; i++) {
            var node = document.querySelector(selectors[i]);
            if (node) {
              return node;
            }
          }
          return null;
        }
        function fireInputEvents(node) {
          if (!node) {
            return;
          }
          try {
            node.dispatchEvent(new Event('input', { bubbles: true }));
            node.dispatchEvent(new Event('change', { bubbles: true }));
            node.dispatchEvent(new Event('blur', { bubbles: true }));
          } catch (_) {
          }
        }
        var usernameInput = pick(usernameSelectors);
        var passwordInput = pick(passwordSelectors);
        if (!usernameInput || !passwordInput) {
          return JSON.stringify({ filled: false });
        }
        usernameInput.value = ${JSON.stringify(username)};
        passwordInput.value = ${JSON.stringify(password)};
        fireInputEvents(usernameInput);
        fireInputEvents(passwordInput);
        window.__HarmonyDoLoginCredentialDraft = {
          username: usernameInput.value || '',
          password: passwordInput.value || ''
        };
        return JSON.stringify({ filled: true });
      } catch (_) {
        return JSON.stringify({ filled: false });
      }
    })();`;
  }

  static buildCaptureCredentialScript(): string {
    return `(function() {
      try {
        var usernameSelectors = ${LoginAutoFillUtils.USERNAME_SELECTOR_SCRIPT};
        var passwordSelectors = ${LoginAutoFillUtils.PASSWORD_SELECTOR_SCRIPT};
        function pick(selectors) {
          for (var i = 0; i < selectors.length; i++) {
            var node = document.querySelector(selectors[i]);
            if (node) {
              return node;
            }
          }
          return null;
        }
        var usernameInput = pick(usernameSelectors);
        var passwordInput = pick(passwordSelectors);
        var draft = window.__HarmonyDoLoginCredentialDraft && typeof window.__HarmonyDoLoginCredentialDraft === 'object'
          ? window.__HarmonyDoLoginCredentialDraft
          : { username: '', password: '' };
        var username = usernameInput && typeof usernameInput.value === 'string' && usernameInput.value.length > 0
          ? usernameInput.value
          : (draft.username || '');
        var password = passwordInput && typeof passwordInput.value === 'string' && passwordInput.value.length > 0
          ? passwordInput.value
          : (draft.password || '');
        return JSON.stringify({ username: username || '', password: password || '' });
      } catch (_) {
        return JSON.stringify({ username: '', password: '' });
      }
    })();`;
  }
}
