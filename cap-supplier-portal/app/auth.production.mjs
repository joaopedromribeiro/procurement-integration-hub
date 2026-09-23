// Production identity is the approuter's XSUAA session and forwarded user token.
// The browser never handles credentials or JWTs. Mutations wait for a CSRF design.
export const mode = 'xsuaa'
export const mutationsEnabled = false
export const session = {
  get: () => true,
  clear: () => {}
}
export const headers = () => ({})
export const displayName = () => 'BTP user'
export const bindControls = () => {}
