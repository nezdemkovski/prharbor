#!/usr/bin/env python3
"""Pull your real open PRs into prototype/data.js for timeline.html.

Requests use the existing GitHub CLI login via gh api. No tokens are read or copied.
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

OUT = Path(__file__).with_name("data.js")
SOURCE = "gh cli"


def gql(query, variables=None):
    environment = dict(os.environ)
    for key in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GH_DEBUG"):
        environment.pop(key, None)
    environment["GH_PROMPT_DISABLED"] = "1"
    environment["GH_PAGER"] = ""
    try:
        response = subprocess.run(
            ["gh", "api", "graphql", "--hostname", "github.com", "--method", "POST", "--input", "-"],
            input=json.dumps({"query": query, "variables": variables or {}}),
            capture_output=True, text=True, timeout=60, env=environment,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        raise RuntimeError("GitHub CLI is unavailable or the request timed out.") from None
    try:
        body = json.loads(response.stdout)
    except ValueError:
        raise RuntimeError("GitHub CLI request failed; check gh auth status in Terminal.") from None
    if body.get("errors"):
        raise RuntimeError("; ".join(e["message"] for e in body["errors"]))
    if response.returncode:
        raise RuntimeError("GitHub CLI request failed; check gh auth status in Terminal.")
    return body["data"]


STACK_FIELDS = "stack { id number baseRefName size } stackEntry { position }"

PR_FIELDS = """
  id number title url createdAt updatedAt isDraft reviewDecision mergeable additions deletions headRefName baseRefName
  author { __typename login avatarUrl }
  repository { name nameWithOwner }
  %s
  commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 60) { nodes {
    __typename
    ... on CheckRun { name conclusion status }
    ... on StatusContext { context state }
  } } } } } }
  reviewRequests(first: 10) { nodes { requestedReviewer { ... on User { login avatarUrl } } } }
  latestReviews(first: 10) { nodes { author { login avatarUrl } state } }
  timelineItems(last: 80, itemTypes: [PULL_REQUEST_COMMIT, PULL_REQUEST_REVIEW, ISSUE_COMMENT,
                                      REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT, HEAD_REF_FORCE_PUSHED_EVENT]) {
    nodes {
      __typename
      ... on PullRequestCommit { commit { committedDate } }
      ... on PullRequestReview { state submittedAt author { __typename login avatarUrl } }
      ... on IssueComment { createdAt author { __typename login avatarUrl } }
      ... on ReviewRequestedEvent { createdAt requestedReviewer { ... on User { login } } }
      ... on ReadyForReviewEvent { createdAt }
      ... on HeadRefForcePushedEvent { createdAt }
    }
  }
"""

SEARCH = """
query($q: String!, $cursor: String) {
  viewer { login avatarUrl }
  search(query: $q, type: ISSUE, first: 40, after: $cursor) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest { %s } }
  }
}
"""


STACK_DETAILS = """
query($ids: [ID!]!) {
  nodes(ids: $ids) {
    ... on PullRequestStack { id entries(first: 100) { nodes { position pullRequest { number title state url } } } }
  }
}
"""


def search(q, with_stacks):
    query = SEARCH % (PR_FIELDS % (STACK_FIELDS if with_stacks else ""))
    nodes, cursor, viewer = [], None, None
    while True:
        data = gql(query, {"q": q, "cursor": cursor})
        viewer = data["viewer"]
        nodes += [n for n in data["search"]["nodes"] if n]
        page = data["search"]["pageInfo"]
        if not page["hasNextPage"]:
            return viewer, nodes
        cursor = page["endCursor"]


def is_bot(actor):
    return not actor or actor.get("__typename") == "Bot" or actor.get("login", "").endswith("[bot]")


def main():
    queries = {
        "author": "is:open is:pr archived:false author:@me",
        "review": "is:open is:pr archived:false review-requested:@me",
        "assignee": "is:open is:pr archived:false assignee:@me",
    }
    with_stacks = True
    results = {}
    for rel, q in queries.items():
        try:
            viewer, results[rel] = search(q, with_stacks)
        except RuntimeError as e:
            if with_stacks and "stack" in str(e).lower():
                with_stacks = False
                viewer, results[rel] = search(q, with_stacks)
            else:
                raise

    me = viewer["login"]
    people = {me: {"name": "You", "avatar": viewer["avatarUrl"]}}
    prs = {}

    def person(actor):
        if actor and actor.get("login") and actor["login"] not in people:
            people[actor["login"]] = {"name": actor["login"], "avatar": actor.get("avatarUrl")}

    for rel, nodes in results.items():
        for n in nodes:
            if n["id"] in prs:
                prs[n["id"]]["relations"].append(rel)
                continue
            author = (n.get("author") or {}).get("login", "ghost")
            person(n.get("author"))
            rollup = ((n["commits"]["nodes"] or [{}])[0].get("commit") or {}).get("statusCheckRollup") or {}
            ci = {"SUCCESS": "pass", "FAILURE": "fail", "ERROR": "fail", "PENDING": "pending", "EXPECTED": "pending"}.get(rollup.get("state"), "none")
            checks = []
            for c in (rollup.get("contexts") or {}).get("nodes") or []:
                if c.get("__typename") == "CheckRun":
                    conclusion = c.get("conclusion")
                    st = ("pending" if conclusion is None else
                          "pass" if conclusion == "SUCCESS" else
                          "skip" if conclusion in ("NEUTRAL", "SKIPPED") else "fail")
                    checks.append({"name": c["name"], "state": st})
                elif c.get("__typename") == "StatusContext":
                    st = {"SUCCESS": "pass", "FAILURE": "fail", "ERROR": "fail"}.get(c.get("state"), "pending")
                    checks.append({"name": c["context"], "state": st})

            reviewers = []
            for rr in n["reviewRequests"]["nodes"]:
                r = rr.get("requestedReviewer") or {}
                name = r.get("login") or (f"team:{r['name']}" if r.get("name") else None)
                if name:
                    reviewers.append(name)
                    person(r if r.get("login") else {"login": name})
            for lr in n["latestReviews"]["nodes"]:
                if lr.get("author") and lr["author"]["login"] not in reviewers and lr["author"]["login"] != author:
                    reviewers.append(lr["author"]["login"])
                    person(lr["author"])

            events = [{"at": n["createdAt"], "type": "opened"}]
            for it in n["timelineItems"]["nodes"]:
                t = it["__typename"]
                if t == "PullRequestCommit":
                    events.append({"at": it["commit"]["committedDate"], "type": "commit"})
                elif t in ("HeadRefForcePushedEvent", "ReadyForReviewEvent"):
                    events.append({"at": it["createdAt"], "type": "commit"})
                elif t == "PullRequestReview" and it.get("submittedAt") and not is_bot(it.get("author")):
                    person(it["author"])
                    kind = {"APPROVED": "approved", "CHANGES_REQUESTED": "changes"}.get(it["state"], "comment")
                    events.append({"at": it["submittedAt"], "type": kind, "who": it["author"]["login"]})
                elif t == "IssueComment" and not is_bot(it.get("author")):
                    person(it["author"])
                    events.append({"at": it["createdAt"], "type": "comment", "who": it["author"]["login"]})
                elif t == "ReviewRequestedEvent" and (it.get("requestedReviewer") or {}).get("login"):
                    events.append({"at": it["createdAt"], "type": "requested", "who": it["requestedReviewer"]["login"]})

            if author == me:
                review = {"APPROVED": "approved", "CHANGES_REQUESTED": "changes"}.get(n.get("reviewDecision"), "none")
            else:
                review = "requested" if rel == "review" else "none"

            stack = None
            if n.get("stack") and n["stack"]["size"] > 1 and n.get("stackEntry"):
                stack = {"id": n["stack"]["id"], "num": n["stack"]["number"],
                         "pos": n["stackEntry"]["position"], "base": n["stack"]["baseRefName"]}

            prs[n["id"]] = {
                "id": n["id"], "repo": n["repository"]["name"], "fullRepo": n["repository"]["nameWithOwner"],
                "num": n["number"], "title": n["title"], "url": n["url"], "author": author,
                "created": n["createdAt"], "draft": n["isDraft"], "ci": ci, "review": review,
                "conflict": n.get("mergeable") == "CONFLICTING", "reviewers": reviewers,
                "add": n["additions"], "del": n["deletions"], "branch": n["headRefName"], "base": n.get("baseRefName"), "checks": checks,
                "stack": stack, "events": sorted(events, key=lambda e: e["at"]), "relations": [rel],
            }

    # Every layer of each stack, merged ones included, so the timeline can show what already landed.
    stack_entries = {}
    stack_ids = sorted({p["stack"]["id"] for p in prs.values() if p["stack"]})
    for i in range(0, len(stack_ids), 100):
        for node in gql(STACK_DETAILS, {"ids": stack_ids[i:i + 100]})["nodes"]:
            if node:
                stack_entries[node["id"]] = [
                    {"pos": e["position"], "num": e["pullRequest"]["number"], "title": e["pullRequest"]["title"],
                     "state": e["pullRequest"]["state"], "url": e["pullRequest"]["url"]}
                    for e in node["entries"]["nodes"] if e.get("pullRequest")
                ]

    payload = {
        "fetchedAt": datetime.now(timezone.utc).isoformat(),
        "me": me, "people": people, "prs": list(prs.values()), "stacks": with_stacks,
        "stackEntries": stack_entries,
    }
    OUT.write_text("window.LIVE = " + json.dumps(payload, indent=1) + ";\n")
    print(f"{len(prs)} open PRs via {SOURCE} → {OUT.name} (stacks: {'yes' if with_stacks else 'unsupported'})")


if __name__ == "__main__":
    main()
