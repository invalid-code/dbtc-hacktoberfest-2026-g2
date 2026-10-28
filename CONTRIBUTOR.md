# CONTRIBUTOR.md

Thank you for contributing to the Greenhouse IoT project!

## How to contribute

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/your-feature`).
3. Make your changes.
4. Ensure the shared contracts stay consistent across `microcontroller/`, `api/`, and `frontend/`.
5. Run the tests:
   - API: `cd api && uv sync --group dev && uv run pytest`
   - Frontend: `cd frontend && flutter test`
6. Commit your changes (`git commit -m 'Add some feature'`).
7. Push to your branch (`git push origin feature/your-feature`).
8. Open a pull request.

## Important notes

- `microcontroller/secrets.h` is git-ignored; never commit credentials.
- Schema changes must include an Alembic migration (`cd api && uv run alembic revision --autogenerate -m "..."`).
- Changes to pump modes, payload shapes, or sensor keys must update the firmware, API schemas, and frontend models together.
- The project uses Apache License 2.0; see `LICENSE`.

## Questions?

Open an issue or start a discussion in the repository.
