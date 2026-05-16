/**
 * Landing page — replace with real content as the project takes shape.
 */
export default function Home() {
  return (
    <main style={{ padding: '2rem', maxWidth: '720px', margin: '0 auto' }}>
      <h1>{{project_name}}</h1>
      <p>{{project_description}}</p>
      <p>
        See <a href="https://{{github_username}}.github.io/{{project_name}}/">documentation</a> for
        setup, architecture, and runbooks.
      </p>
    </main>
  );
}
