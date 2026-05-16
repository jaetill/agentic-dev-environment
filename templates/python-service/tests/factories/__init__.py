"""Factory data generators per ADR-0006 §6 and ADR-0004.

Use factory_boy to generate synthetic test data. Production data must NEVER
be used in non-prod environments (ADR-0006). Each factory is responsible for:

- Producing valid, realistic-but-synthetic data
- Respecting PII tags in the data model (per ADR-0006)
- Being deterministic when given a seed (for reproducible tests)

Example:

    import factory
    from {{project_slug}}.models import User

    class UserFactory(factory.Factory):
        class Meta:
            model = User
        email = factory.Sequence(lambda n: f"alice{n}@example.test")
        display_name = factory.Sequence(lambda n: f"Alice {n}")
"""
