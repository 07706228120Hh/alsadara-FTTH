"""add snmpv3 fields, ont optical fields, alarm normalizer, devicehealth, ponportstatus

Revision ID: 3f8a21d6c094
Revises: c902d37b1884
Create Date: 2026-07-21 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# مُعرّفات الهجرة، يستخدمها Alembic.
revision: str = '3f8a21d6c094'
down_revision: Union[str, None] = 'c902d37b1884'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # -----------------------------------------------------------------------
    # 1. توسيع oltdevice — حقول SNMPv3
    # -----------------------------------------------------------------------
    with op.batch_alter_table('oltdevice', schema=None) as batch_op:
        batch_op.add_column(sa.Column('snmp_enabled', sa.Boolean(), nullable=False, server_default='1'))
        batch_op.add_column(sa.Column('snmp_port', sa.Integer(), nullable=False, server_default='161'))
        batch_op.add_column(sa.Column('snmp_user', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default='platform-monitor'))
        batch_op.add_column(sa.Column('snmp_auth_proto', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default='SHA256'))
        batch_op.add_column(sa.Column('snmp_auth_key_enc', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('snmp_priv_proto', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default='AES'))
        batch_op.add_column(sa.Column('snmp_priv_key_enc', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('snmp_context', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('snmp_engine_id', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('adapter_profile', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))

    # -----------------------------------------------------------------------
    # 2. توسيع ontrecord — حقول القراءة الضوئية/التفصيلية
    # -----------------------------------------------------------------------
    with op.batch_alter_table('ontrecord', schema=None) as batch_op:
        batch_op.add_column(sa.Column('tx_power', sa.Float(), nullable=True))
        batch_op.add_column(sa.Column('olt_rx_power', sa.Float(), nullable=True))
        batch_op.add_column(sa.Column('temperature', sa.Float(), nullable=True))
        batch_op.add_column(sa.Column('voltage', sa.Float(), nullable=True))
        batch_op.add_column(sa.Column('bias_current', sa.Float(), nullable=True))
        batch_op.add_column(sa.Column('last_up', sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column('last_down', sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column('last_down_cause', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('ont_model', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('hw_version', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('sw_version', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('reg_method', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))

    # -----------------------------------------------------------------------
    # 3. توسيع alarmrecord — حقول تطبيع الإنذار
    # -----------------------------------------------------------------------
    with op.batch_alter_table('alarmrecord', schema=None) as batch_op:
        batch_op.add_column(sa.Column('alarm_uid', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('source_type', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('frame', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('slot', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('pon', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('ont_id_ref', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('code', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('title', sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=''))
        batch_op.add_column(sa.Column('occurred_at', sa.DateTime(), nullable=True))
        batch_op.create_index(batch_op.f('ix_alarmrecord_alarm_uid'), ['alarm_uid'], unique=False)

    # -----------------------------------------------------------------------
    # 4. جدول جديد: devicehealth
    # -----------------------------------------------------------------------
    op.create_table('devicehealth',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('olt_id', sa.Integer(), nullable=False),
        sa.Column('cpu', sa.Float(), nullable=True),
        sa.Column('memory', sa.Float(), nullable=True),
        sa.Column('temperature', sa.Float(), nullable=True),
        sa.Column('uptime', sa.Integer(), nullable=True),
        sa.Column('power_status', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('fan_status', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('sw_version', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('active_alarms', sa.Integer(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['olt_id'], ['oltdevice.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('devicehealth', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_devicehealth_olt_id'), ['olt_id'], unique=True)

    # -----------------------------------------------------------------------
    # 5. جدول جديد: ponportstatus
    # -----------------------------------------------------------------------
    op.create_table('ponportstatus',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('olt_id', sa.Integer(), nullable=False),
        sa.Column('frame', sa.Integer(), nullable=False),
        sa.Column('slot', sa.Integer(), nullable=False),
        sa.Column('port', sa.Integer(), nullable=False),
        sa.Column('status', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('tech', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('onts_registered', sa.Integer(), nullable=False),
        sa.Column('onts_online', sa.Integer(), nullable=False),
        sa.Column('onts_offline', sa.Integer(), nullable=False),
        sa.Column('rx_traffic', sa.Float(), nullable=True),
        sa.Column('tx_traffic', sa.Float(), nullable=True),
        sa.Column('utilization', sa.Float(), nullable=True),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['olt_id'], ['oltdevice.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('ponportstatus', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_ponportstatus_olt_id'), ['olt_id'], unique=False)


def downgrade() -> None:
    # -----------------------------------------------------------------------
    # 5. حذف ponportstatus
    # -----------------------------------------------------------------------
    with op.batch_alter_table('ponportstatus', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_ponportstatus_olt_id'))
    op.drop_table('ponportstatus')

    # -----------------------------------------------------------------------
    # 4. حذف devicehealth
    # -----------------------------------------------------------------------
    with op.batch_alter_table('devicehealth', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_devicehealth_olt_id'))
    op.drop_table('devicehealth')

    # -----------------------------------------------------------------------
    # 3. إزالة حقول تطبيع الإنذار من alarmrecord
    # -----------------------------------------------------------------------
    with op.batch_alter_table('alarmrecord', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_alarmrecord_alarm_uid'))
        batch_op.drop_column('occurred_at')
        batch_op.drop_column('title')
        batch_op.drop_column('code')
        batch_op.drop_column('ont_id_ref')
        batch_op.drop_column('pon')
        batch_op.drop_column('slot')
        batch_op.drop_column('frame')
        batch_op.drop_column('source_type')
        batch_op.drop_column('alarm_uid')

    # -----------------------------------------------------------------------
    # 2. إزالة حقول القراءة الضوئية من ontrecord
    # -----------------------------------------------------------------------
    with op.batch_alter_table('ontrecord', schema=None) as batch_op:
        batch_op.drop_column('reg_method')
        batch_op.drop_column('sw_version')
        batch_op.drop_column('hw_version')
        batch_op.drop_column('ont_model')
        batch_op.drop_column('last_down_cause')
        batch_op.drop_column('last_down')
        batch_op.drop_column('last_up')
        batch_op.drop_column('bias_current')
        batch_op.drop_column('voltage')
        batch_op.drop_column('temperature')
        batch_op.drop_column('olt_rx_power')
        batch_op.drop_column('tx_power')

    # -----------------------------------------------------------------------
    # 1. إزالة حقول SNMPv3 من oltdevice
    # -----------------------------------------------------------------------
    with op.batch_alter_table('oltdevice', schema=None) as batch_op:
        batch_op.drop_column('adapter_profile')
        batch_op.drop_column('snmp_engine_id')
        batch_op.drop_column('snmp_context')
        batch_op.drop_column('snmp_priv_key_enc')
        batch_op.drop_column('snmp_priv_proto')
        batch_op.drop_column('snmp_auth_key_enc')
        batch_op.drop_column('snmp_auth_proto')
        batch_op.drop_column('snmp_user')
        batch_op.drop_column('snmp_port')
        batch_op.drop_column('snmp_enabled')
