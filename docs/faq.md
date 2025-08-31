# FAQ

**Q: Does this overwrite my current files?**  
By default, stow refuses to clobber. Use `--adopt` to bring files under management, or `--delete` to unlink previous symlinks.

**Q: Can I use only part of the setup?**  
Yes. Either edit `packages.txt` or pass package names to `apply`.

**Q: How do I keep secrets out of Git?**  
Never commit tokens/passwords. Use OS keychains/1Password; for configs that need secrets, source them from ignored files.

**Q: How do I try changes safely?**  
Work in a branch. Use `./apply.sh --no` to see effects, then `--restow` to apply.

**Q: Why stow on Unix and PowerShell on Windows?**  
It keeps platform ergonomics: stow is simple and ubiquitous on Unix; PowerShell gives precise control on Windows.
