"""Checks the sandbox SCP keeps every way out closed, except the one
attachment to work's network that IT's own role may make."""
import json
from pathlib import Path

SCP = json.loads((Path(__file__).parent.parent / "scp-no-internet.json").read_text())
IT_ROLE = "arn:aws:iam::*:role/<it-network-role>"
ATTACH = {
    "ec2:CreateTransitGatewayVpcAttachment",
    "ec2:AcceptTransitGatewayVpcAttachment",
    "networkmanager:*",
    "ram:AcceptResourceShareInvitation",
}


def statements_denying(action):
    return [s for s in SCP["Statement"] if s["Effect"] == "Deny" and action in s["Action"]]


def test_attachment_actions_are_denied_to_everyone_but_it():
    for action in ATTACH:
        found = statements_denying(action)
        assert len(found) == 1, action
        cond = found[0].get("Condition", {})
        assert cond == {"ArnNotLike": {"aws:PrincipalArn": IT_ROLE}}, action


def test_no_one_can_build_their_own_way_out():
    for action in [
        "ec2:CreateInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:CreateTransitGateway",
        "ec2:CreateVpcPeeringConnection",
        "ec2:CreateVpnConnection",
    ]:
        found = statements_denying(action)
        assert len(found) == 1 and "Condition" not in found[0], action
