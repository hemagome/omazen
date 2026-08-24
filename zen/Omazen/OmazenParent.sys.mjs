/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

// Parent side intentionally has no callable surface. The chrome bridge only
// uses the inherited sendAsyncMessage method to push validated palette data.
export class OmazenParent extends JSWindowActorParent {}
