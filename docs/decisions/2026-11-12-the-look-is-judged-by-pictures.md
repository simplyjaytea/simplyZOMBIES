# The look is delegated, and it is judged by pictures

- **Date:** 2026-11-12
- **Decided by:** the owner (the delegation); engineering (how it is judged)
- **Systems:** the first-person look (`godot/presentation/first_person/`, [docs/46](../46-the-look.md)), the workflow

**Decision.** The owner handed over the look of the first-person game: "do whatever you think you
need to do ... just make the game beautiful." Until the owner says otherwise, a visible change to
the first-person picture is an engineering call inside [docs/46](../46-the-look.md), and is no
longer a card that waits. What does not move: the hardcore contract, the spatial contract, the
standing bans, and every owner ruling docs/46 lists under "The law a picture keeps".

A change to the look is judged three ways, and a pull request carries all three: before and after
pictures from the look sheet (`npm run godot:shots:look`), read by a critic who did not build the
change; the structure lanes of `npm run godot:check:fp_look`, each with a plant that ends red; and
the frame cost of the same stations (`npm run godot:frames:look`), before and after. The owner
sees the pairs in the pull request and can send any of it back; the merge does not wait for that.

**Why.** Every look decision used to be an owner card with a default, and the picture stayed a
grey box: a flat sky, no shadows, a board of flat ground tiles, trees drawn as boxes. The only
review pictures were throwaway drivers kept outside the repository, and the last one was lost
(#404). A look cannot be argued in prose and cannot be judged by a gate alone, so the pictures
became the evidence and the driver that makes them is in the repository.

**Instead of.**

- Keeping each visible change as an owner card: the owner asked for the opposite.
- A pixel gate (golden images in CI): the renderer differs between machines, and a golden image
  freezes the look it was meant to let improve.
- Judging by the structure gate alone: it can prove a sky shader is installed and cannot say
  whether the sky is any good.
