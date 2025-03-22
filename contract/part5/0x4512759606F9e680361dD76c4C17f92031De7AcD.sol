// SPDX-License-Identifier: MIT
/*

     ᴅɪɪᴅ ᴀɴᴅ ʜɪɢɢs ᴘʀᴇsᴇɴᴛ        __         
.----.-----.-----.----.----.-----.|  |_.-----.
|  __|  _  |     |  __|   _|  -__||   _|  -__|
|____|_____|__|__|____|__| |_____||____|_____|

*/

pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "solady/src/utils/SSTORE2.sol";
import "solady/src/utils/Base64.sol";

import "./NeuralNetwork.sol";

contract Concrete is ERC721A, Ownable(msg.sender), NeuralNetwork {
    struct Token {
        uint128 input;
        string hash;
        address[] image;
        string title;
        string description;
        bool unrevealed;
    }

    string prefix =
        "https://firebasestorage.googleapis.com/v0/b/higgsdotart.firebasestorage.app/o/generated_artwork%252F";
    string suffix = ".png?alt=media";

    uint startingPrice = 0.25 ether;
    uint settlingPrice = 0.1 ether;
    uint startTime = 1740682800;

    uint maxSupply = 512;

    mapping(uint256 => Token) public tokens;
    mapping(uint128 => bool) public inputTaken;

    constructor() ERC721A("Concrete", "CONCRETE") {}

    ///////////////////////////////
    ///////    HELPERS      ///////
    ///////////////////////////////

    function getPrice() public view returns (uint) {
        if (!mintStarted()) {
            return startingPrice;
        }

        uint hrs = (block.timestamp - startTime) / 7200;

        uint price = startingPrice - (hrs * 0.0025 ether);

        if (price < settlingPrice) {
            price = settlingPrice;
        }

        return price;
    }

    function mintStarted() public view returns (bool) {
        return block.timestamp >= startTime;
    }

    function setStartTime(uint newStartTime) external onlyOwner {
        startTime = newStartTime;
    }

    ///////////////////////////////
    ///////    PUBLIC       ///////
    ///////////////////////////////

    function mint(uint128 input) external payable {
        uint256 tokenId = _nextTokenId();

        if (input == 0) {
            unchecked {
                input = uint128(
                    uint256(
                        keccak256(abi.encodePacked(block.timestamp, tokenId))
                    )
                );
            }
        }

        require(tokenId <= maxSupply, "Max supply reached");
        require(mintStarted() || msg.sender == owner(), "Mint not started");
        require(
            msg.value == getPrice() || msg.sender == owner(),
            "Invalid price"
        );
        require(!inputTaken[input], "Input already taken");

        inputTaken[input] = true;

        tokens[tokenId].input = input;

        _mint(msg.sender, 1);
    }

    function setUnrevealed(uint256 tokenId, bool unrevealed) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");

        tokens[tokenId].unrevealed = unrevealed;
    }

    ///////////////////////////////
    ///////    TOKEN URI    ///////
    ///////////////////////////////

    function setImage(uint256 tokenId, bytes[] calldata image) internal {
        // loop through the image array, appending a new byte array
        // to the chunks. This is because the contract storage limit
        // is 24576 but we actually get much further than that before
        // running out of gas in the block.
        for (uint8 i = 0; i < image.length; i++) {
            tokens[tokenId].image.push(SSTORE2.write(image[i]));
        }
    }

    function updateToken(
        uint256 tokenId,
        bytes[] calldata image,
        string calldata title,
        string calldata description,
        string calldata hash
    ) external onlyOwner {
        if (image.length > 0) {
            delete tokens[tokenId].image;
            setImage(tokenId, image);
        }

        if (bytes(title).length > 0) {
            tokens[tokenId].title = title;
        }

        if (bytes(description).length > 0) {
            tokens[tokenId].description = description;
        }

        if (bytes(hash).length != 32) {
            tokens[tokenId].hash = hash;
        }
    }

    function wrap(
        string memory imageUri,
        string memory mimetype
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<svg viewBox="0 0 800 1200" width="800" height="1200" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><style>image {image-rendering: optimizeSpeed;image-rendering: -moz-crisp-edges;image-rendering: -o-crisp-edges;image-rendering: -webkit-optimize-contrast;image-rendering: optimize-contrast;image-rendering: crisp-edges;image-rendering: pixelated;-ms-interpolation-mode: nearest-neighbor;}</style></defs><image width="800px" height="1200px" href="data:image/',
                    mimetype,
                    ";base64,",
                    imageUri,
                    '" /><foreignObject width="800px" height="1200px"><div xmlns="http://www.w3.org/1999/xhtml" style="width:800px; height:1200px;"><img style="width:800px; height:1200px; image-rendering: optimizeSpeed; image-rendering: -moz-crisp-edges; image-rendering: -o-crisp-edges; image-rendering: -webkit-optimize-contrast; image-rendering: optimize-contrast; image-rendering: crisp-edges; image-rendering: pixelated; -ms-interpolation-mode: nearest-neighbor;" src="data:image/',
                    mimetype,
                    ";base64,",
                    imageUri,
                    '" /></div></foreignObject></svg>'
                )
            );
    }

    function render(uint128 input) internal view returns (bytes memory) {
        uint8[288] memory output = inference(input);

        bytes memory bmp = new bytes(0x344);

        // BMP Header
        bmp[0] = 0x42; // B
        bmp[1] = 0x4D; // M
        bmp[2] = 0x58;
        bmp[3] = 0x01;
        bmp[10] = 0x36; // Pixel array offset

        // DIB Header
        bmp[14] = 0x28; // DIB header size
        bmp[18] = 0x08; // Width: 8px
        bmp[22] = 0xF4; // Height: 12px
        bmp[23] = 0xFF;
        bmp[24] = 0xFF;
        bmp[25] = 0xFF;
        bmp[26] = 0x01; // Color planes
        bmp[28] = 0x18; // Bits per pixel (24)

        for (uint256 i = 0; i < 12; i++) {
            for (uint256 j = 0; j < 8; j++) {
                uint x = (i * 8 + j) * 3;
                bmp[0x36 + x] = bytes1(output[x + 2]);
                bmp[0x36 + x + 1] = bytes1(output[x + 1]);
                bmp[0x36 + x + 2] = bytes1(output[x]);
            }
        }

        return bmp;
    }

    function fingerprintSvg(uint128 input) public view returns (string memory) {
        return wrap(Base64.encode(render(input)), "bmp");
    }

    function fingerprintUri(uint128 input) public view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:image/svg+xml;base64,",
                    Base64.encode(bytes(fingerprintSvg(input)))
                )
            );
    }

    function loadRawImage(
        uint256 tokenId
    ) internal view returns (bytes memory) {
        bytes memory data;

        for (uint8 i = 0; i < tokens[tokenId].image.length; i++) {
            data = abi.encodePacked(
                data,
                SSTORE2.read(tokens[tokenId].image[i])
            );
        }

        return data;
    }

    function loadImage(uint256 tokenId) internal view returns (string memory) {
        bytes memory data = loadRawImage(tokenId);

        return
            string(
                abi.encodePacked(
                    "data:image/svg+xml;base64,",
                    Base64.encode(bytes(wrap(Base64.encode(data), "png")))
                )
            );
    }

    function getTokenImageUri(
        uint256 tokenId
    ) internal view returns (string memory) {
        if (
            (tokens[tokenId].image.length == 0 &&
                bytes(tokens[tokenId].hash).length == 0) ||
            tokens[tokenId].unrevealed
        ) {
            return fingerprintUri(tokens[tokenId].input);
        }

        if (tokens[tokenId].image.length > 0) {
            return loadImage(tokenId);
        }

        return string(abi.encodePacked(prefix, tokens[tokenId].hash, suffix));
    }

    function getTitle(uint256 tokenId) internal view returns (string memory) {
        if (bytes(tokens[tokenId].title).length > 0) {
            return tokens[tokenId].title;
        }

        return
            string(abi.encodePacked("Concrete #", Strings.toString(tokenId)));
    }

    function getDescription(
        uint256 tokenId
    ) internal view returns (string memory) {
        if (bytes(tokens[tokenId].description).length > 0) {
            return tokens[tokenId].description;
        }

        return "";
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    'data:application/json;utf8,{"image":"',
                    getTokenImageUri(tokenId),
                    '","name":"',
                    getTitle(tokenId),
                    '","description":"',
                    getDescription(tokenId),
                    '"}'
                )
            );
    }

    ///////////////////////////////
    ///////    OWNER ONLY    ///////
    ///////////////////////////////

    function setWeights(
        bytes calldata weights,
        uint256 index
    ) public onlyOwner {
        _setWeights(weights, index);
    }

    function withdraw() external onlyOwner {
        (bool s, ) = owner().call{value: (address(this).balance)}("");
        require(s, "Withdraw failed.");
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }
}