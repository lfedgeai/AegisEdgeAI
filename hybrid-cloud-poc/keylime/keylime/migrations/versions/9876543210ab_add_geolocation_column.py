"""Add geolocation column

Revision ID: 9876543210ab
Revises: 57b24ee21dfa
Create Date: 2025-12-23 12:00:00.000000

"""
import sqlalchemy as sa
from alembic import op
import keylime.db.verifier_db
import keylime.json

# revision identifiers, used by Alembic.
revision = "9876543210ab"
down_revision = "57b24ee21dfa"
branch_labels = None
depends_on = None


def upgrade(engine_name):
    globals()[f"upgrade_{engine_name}"]()


def downgrade(engine_name):
    globals()[f"downgrade_{engine_name}"]()


def upgrade_registrar():
    pass


def downgrade_registrar():
    pass


def upgrade_cloud_verifier():
    with op.batch_alter_table("verifiermain") as batch_op:
        batch_op.add_column(
            sa.Column(
                "geolocation",
                keylime.db.verifier_db.JSONPickleType(pickler=keylime.json.JSONPickler),
                nullable=True
            )
        )


def downgrade_cloud_verifier():
    with op.batch_alter_table("verifiermain") as batch_op:
        batch_op.drop_column("geolocation")
