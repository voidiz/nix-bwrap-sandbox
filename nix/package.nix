{
  lib,
  stdenv,
  makeWrapper,
  bash,
  nix,
  bubblewrap,
  git,
  self,
}:
stdenv.mkDerivation {
  pname = "bwrap-sandbox";
  version = self.shortRev or "dirty";

  src = lib.cleanSource self;

  nativeBuildInputs = [makeWrapper];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/nix-bwrap-sandbox $out/bin

    cp $src/flake.nix $src/flake.lock $out/share/nix-bwrap-sandbox/
    cp -r $src/nix $out/share/nix-bwrap-sandbox/nix
    cp $src/bwrap-sandbox.sh $out/share/nix-bwrap-sandbox/bwrap-sandbox.sh
    chmod +x $out/share/nix-bwrap-sandbox/bwrap-sandbox.sh

    mkdir -p $out/share/nix-bwrap-sandbox/sandbox-home
    cp -r $src/sandbox-home/. $out/share/nix-bwrap-sandbox/sandbox-home/

    makeWrapper $out/share/nix-bwrap-sandbox/bwrap-sandbox.sh $out/bin/bwrap-sandbox \
      --set BWRAP_SANDBOX_FLAKE_DIR $out/share/nix-bwrap-sandbox \
      --prefix PATH : ${lib.makeBinPath [bash nix bubblewrap git]}

    runHook postInstall
  '';

  meta = with lib; {
    license = licenses.mit;
    platforms = ["x86_64-linux" "aarch64-linux"];
    mainProgram = "bwrap-sandbox";
  };
}
