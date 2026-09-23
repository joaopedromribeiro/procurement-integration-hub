// Development-only mock identity. The approuter build substitutes auth.production.mjs.
export const mode = 'mock'
export const mutationsEnabled = true

export const session = {
  get() {
    const raw = sessionStorage.getItem('portal-user')
    return raw ? JSON.parse(raw) : null
  },
  set(username, password) {
    sessionStorage.setItem('portal-user', JSON.stringify({ username, password }))
  },
  clear() {
    sessionStorage.removeItem('portal-user')
  }
}

export function headers() {
  const user = session.get()
  return user ? { Authorization: `Basic ${btoa(`${user.username}:${user.password}`)}` } : {}
}

export const displayName = user => user.username

export function bindControls({ onSignIn, onSignOut }) {
  document.getElementById('signin-form').addEventListener('submit', event => {
    event.preventDefault()
    session.set(
      document.getElementById('username').value.trim(),
      document.getElementById('password').value
    )
    onSignIn()
  })
  document.getElementById('signout').addEventListener('click', () => {
    session.clear()
    onSignOut()
  })
}
