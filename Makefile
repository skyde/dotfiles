.PHONY: stow restow unstow stow-dry apply update diff

DOT := ./dot

stow:
	@$(DOT) apply

restow:
	@$(DOT) restow

unstow:
	@$(DOT) delete

stow-dry:
	@$(DOT) apply --dry-run

apply:
	@$(DOT) apply

update:
	@$(DOT) update

diff:
	@$(DOT) diff
