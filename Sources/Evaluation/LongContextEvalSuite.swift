// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation

// MARK: - Long Context Eval Suite

extension BuiltInEvalSuites {

    /// Tests the model's ability to process and retrieve information from long
    /// multi-paragraph contexts.
    ///
    /// Each prompt includes a 500+ word passage followed by a retrieval question.
    /// This evaluates context window utilization, attention over long sequences,
    /// and factual extraction from dense text. Uses `timeoutSeconds: 120` to
    /// allow for longer inference on large inputs.
    ///
    /// 8 prompts covering science, history, technology, and narrative passages.
    static let longContext = EvalSuite(
        name: "Long Context",
        description: "Tests information retrieval and comprehension from multi-paragraph passages of 500+ words each, evaluating context window utilization and attention.",
        category: .reasoning,
        prompts: [
            // 1. Science passage — photosynthesis
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                Photosynthesis is the biological process by which green plants, algae, and certain bacteria convert light energy into chemical energy stored in glucose molecules. This process is fundamental to life on Earth, as it provides the primary source of organic compounds and oxygen for nearly all living organisms. The process occurs primarily in the chloroplasts of plant cells, specifically within structures called thylakoids, which contain the pigment chlorophyll. Chlorophyll absorbs light most efficiently in the blue and red wavelengths, reflecting green light, which is why most plants appear green to our eyes.

                The process of photosynthesis can be divided into two main stages: the light-dependent reactions and the light-independent reactions, also known as the Calvin cycle. During the light-dependent reactions, which take place in the thylakoid membranes, chlorophyll absorbs photons of light energy. This energy is used to split water molecules into hydrogen ions, electrons, and oxygen gas. The oxygen is released as a byproduct, which is critical for aerobic respiration in animals and other organisms. The electrons pass through a series of proteins known as the electron transport chain, generating ATP (adenosine triphosphate) and NADPH, which are energy-carrying molecules.

                The Calvin cycle, named after Melvin Calvin who discovered it in the 1950s, takes place in the stroma of the chloroplast. During this stage, the ATP and NADPH produced in the light-dependent reactions are used to fix carbon dioxide from the atmosphere into organic molecules through a process called carbon fixation. The enzyme RuBisCO (ribulose-1,5-bisphosphate carboxylase/oxygenase) plays a critical role in this process, catalyzing the attachment of carbon dioxide to a five-carbon sugar called RuBP (ribulose bisphosphate). Through a series of chemical reactions, the fixed carbon is eventually converted into glucose, which the plant can use for energy or as a building block for other organic molecules such as cellulose, starch, and amino acids.

                Environmental factors significantly affect the rate of photosynthesis. Light intensity, carbon dioxide concentration, temperature, and water availability all play important roles. At low light intensities, the rate of photosynthesis increases linearly with increasing light. However, at higher intensities, the rate plateaus as the photosynthetic machinery becomes saturated. Similarly, increasing carbon dioxide concentration generally increases the rate of photosynthesis up to a point, after which other factors become limiting. Temperature affects the enzymes involved in photosynthesis, with most plants having an optimal temperature range between 25 and 35 degrees Celsius. Above or below this range, enzyme activity decreases, reducing the rate of photosynthesis.

                Recent research has focused on improving photosynthetic efficiency to address global food security challenges. Scientists are exploring genetic modifications to RuBisCO to increase its efficiency, as well as engineering C4 photosynthesis pathways into C3 plants like rice and wheat. Some researchers are also investigating artificial photosynthesis systems that could produce clean fuels directly from sunlight and water.

                Question: What enzyme plays a critical role in the Calvin cycle, and what does it catalyze?
                """,
                expectedBehavior: .containsText("RuBisCO"),
                timeoutSeconds: 120
            ),

            // 2. History passage — Industrial Revolution
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                The Industrial Revolution, which began in Britain in the late 18th century, fundamentally transformed human society from agrarian economies to industrial powerhouses. This period of rapid technological and social change began around 1760 and continued through the mid-19th century, though its effects reverberated for decades beyond. The revolution was characterized by the transition from hand production methods to machine manufacturing, the development of new chemical and iron production processes, the increasing use of steam power and water power, the development of machine tools, and the rise of the mechanized factory system.

                The textile industry was one of the first to be transformed. Before the Industrial Revolution, spinning and weaving were cottage industries, with workers producing cloth in their homes using simple hand-powered machines. The invention of the spinning jenny by James Hargreaves in 1764 allowed a single worker to operate multiple spindles simultaneously, dramatically increasing thread production. Richard Arkwright's water frame, patented in 1769, used water power to drive the spinning machinery, producing stronger thread suitable for warp yarns. Samuel Crompton's spinning mule, introduced in 1779, combined features of both the spinning jenny and the water frame, producing fine yet strong yarn. These innovations, combined with Edmund Cartwright's power loom of 1785, transformed textile production from a manual craft into a mechanized industry.

                The development of the steam engine was perhaps the most significant technological advance of the era. While Thomas Newcomen had developed an early atmospheric engine in 1712 for pumping water from mines, it was James Watt's improvements, beginning in 1769, that made steam power truly versatile. Watt's separate condenser dramatically improved efficiency, and his later innovations, including the double-acting engine and the rotative engine, allowed steam power to be applied to a wide range of industrial applications beyond mining. The partnership between Watt and the businessman Matthew Boulton proved instrumental in commercializing these improvements and making steam engines widely available.

                The revolution also brought profound social changes. Urbanization accelerated as workers migrated from rural areas to factory towns and cities. Manchester, for example, grew from a small town of about 25,000 in 1772 to a major industrial city of over 300,000 by 1850. Working conditions in early factories were often harsh, with long hours, dangerous machinery, and inadequate ventilation. Child labor was widespread, with children as young as five working in factories and mines. These conditions eventually led to reform movements and legislation, such as the Factory Acts, which gradually improved worker protections.

                Transportation was revolutionized by the steam engine as well. George Stephenson's Rocket locomotive, which won the Rainhill Trials in 1829, demonstrated the viability of steam-powered rail transport. The opening of the Liverpool and Manchester Railway in 1830 marked the beginning of the railway age, which would transform commerce, travel, and the very concept of time and distance. Railways enabled rapid movement of goods and people across the country, stimulating economic growth and creating new industries.

                The legacy of the Industrial Revolution extends far beyond its technological achievements. It fundamentally altered social structures, created new economic systems, and established patterns of production and consumption that continue to shape our world today.

                Question: What three spinning inventions preceded the power loom, and who invented each one?
                """,
                expectedBehavior: .containsAll(["Hargreaves", "Arkwright", "Crompton"]),
                timeoutSeconds: 120
            ),

            // 3. Technology passage — Internet history
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                The history of the Internet stretches back further than most people realize, with its roots firmly planted in Cold War-era military research. In the late 1960s, the United States Department of Defense's Advanced Research Projects Agency (ARPA) began developing a computer network called ARPANET. The project was driven by the need for a communication system that could survive a nuclear attack — one where the destruction of any single node would not bring down the entire network. The first successful message on ARPANET was sent on October 29, 1969, from a computer at UCLA to one at the Stanford Research Institute. The intended message was LOGIN, but the system crashed after transmitting just the first two letters, LO, making the first Internet message an unintentionally prophetic fragment.

                Throughout the 1970s, researchers worked on developing protocols that would allow different computer networks to communicate with each other. Vint Cerf and Bob Kahn published a landmark paper in 1974 describing TCP (Transmission Control Protocol), which was later split into TCP and IP (Internet Protocol). This TCP/IP protocol suite became the foundation of the modern Internet, providing a universal standard for data transmission. On January 1, 1983 — a date often referred to as the "birthday of the Internet" — ARPANET officially adopted TCP/IP, replacing the earlier NCP (Network Control Protocol).

                The creation of the World Wide Web in 1989 by Tim Berners-Lee at CERN, the European Organization for Nuclear Research, represented another transformative moment. Berners-Lee proposed a system of interlinked hypertext documents accessed via the Internet. He developed three fundamental technologies: HTML (HyperText Markup Language) for creating web pages, HTTP (HyperText Transfer Protocol) for transmitting them, and URLs (Uniform Resource Locators) for addressing them. The first website, info.cern.ch, went live on December 20, 1990, and described the World Wide Web project itself.

                The introduction of the Mosaic web browser in 1993, developed at the National Center for Supercomputing Applications (NCSA) at the University of Illinois, brought the Web to a mass audience. Mosaic was one of the first browsers to display images inline with text rather than in separate windows, making web pages visually appealing for the first time. Marc Andreessen, one of Mosaic's developers, went on to co-found Netscape Communications, whose Navigator browser dominated the market in the mid-1990s before being overtaken by Microsoft's Internet Explorer in the so-called "browser wars."

                The commercialization of the Internet accelerated rapidly in the mid-1990s. Amazon was founded by Jeff Bezos in 1994 as an online bookstore, while eBay, founded by Pierre Omidyar in 1995, created a new model for online auctions. The dot-com boom of the late 1990s saw massive investment in Internet-based companies, many of which had little revenue or viable business models. The bubble burst in March 2000, with the NASDAQ composite index losing nearly 80 percent of its value by October 2002, wiping out trillions of dollars in market capitalization.

                Despite the dot-com crash, the Internet continued to evolve. The emergence of Web 2.0 in the mid-2000s brought user-generated content platforms like YouTube (2005), Facebook (which opened to the general public in 2006), and Twitter (2006). Cloud computing services, pioneered by Amazon Web Services starting in 2006, fundamentally changed how software was built and deployed. Today, the Internet connects billions of devices worldwide and has become essential infrastructure for commerce, communication, education, and entertainment.

                Question: What date is referred to as the "birthday of the Internet" and what protocol transition happened on that date?
                """,
                expectedBehavior: .containsAll(["January 1, 1983", "TCP/IP"]),
                timeoutSeconds: 120
            ),

            // 4. Narrative passage — exploration
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                The race to reach the South Pole in 1911-1912 remains one of the most dramatic episodes in the history of exploration. Two expeditions set out with the same goal: to be the first to reach the southernmost point on Earth. The Norwegian expedition, led by Roald Amundsen, and the British expedition, led by Robert Falcon Scott, employed fundamentally different strategies that would ultimately determine their fates.

                Amundsen's approach was methodical and ruthlessly practical. He chose to establish his base camp at the Bay of Whales on the Ross Ice Shelf, approximately 60 miles closer to the Pole than Scott's base at Cape Evans on Ross Island. Amundsen was an experienced polar traveler who had spent years living with the Inuit people of the Canadian Arctic, learning their survival techniques. He relied exclusively on dog sleds for transportation, using teams of Greenland huskies that were well-adapted to polar conditions. His team consisted of just five men on the final push to the Pole, all of them expert skiers and dog handlers. They established supply depots along their route with generous margins, marking each one with a line of flags extending several miles on either side to ensure they could be found even in whiteout conditions.

                Scott's expedition, by contrast, was far more complex and arguably more scientifically ambitious. Scott chose a combination of motorized sledges, Manchurian ponies, and man-hauling (pulling sledges by human power) for transportation. The motorized sledges broke down early in the journey, and the ponies, poorly suited to Antarctic conditions, had to be shot at the foot of the Beardmore Glacier. For the final 400-mile push across the polar plateau, Scott's team relied entirely on man-hauling, a method that required enormous physical effort and caloric expenditure. Scott's team on the final push consisted of five men instead of the planned four — he made a last-minute decision to add Lieutenant Henry Bowers to the polar party, which strained their supplies.

                Amundsen's team reached the South Pole on December 14, 1911, after a journey of 57 days from their base camp. They spent three days at the Pole, taking observations and leaving a tent with letters for Scott and King Haakon of Norway. The return journey went smoothly, and the entire team arrived back at the Bay of Whales on January 25, 1912, in good health and with eleven surviving dogs.

                Scott's team reached the Pole on January 17, 1912, 34 days after Amundsen. The discovery that they had been beaten was devastating to morale. The return journey became a nightmare of deteriorating weather, dwindling supplies, and physical decline. Edgar Evans, the strongest man in the party, suffered a head injury and died on February 17. Lawrence Oates, suffering from severe frostbite, famously walked out of the tent into a blizzard on March 17, saying "I am just going outside and may be some time." Scott, Edward Wilson, and Bowers made their final camp on March 19, just 11 miles from a supply depot that could have saved them. They died in their tent during a prolonged blizzard, with Scott's last diary entry dated March 29, 1912. Their bodies were found by a search party on November 12, 1912.

                The contrasting outcomes of these two expeditions have been analyzed extensively by historians and survival experts. Key factors included Amundsen's superior knowledge of dog sledding, his more conservative logistics planning, his closer starting point, and his single-minded focus on reaching the Pole. Scott's expedition, while ultimately tragic, contributed significantly to scientific knowledge through the geological specimens and meteorological data the team collected throughout their journey.

                Question: How many miles was Scott's final camp from the supply depot that could have saved his team?
                """,
                expectedBehavior: .containsText("11"),
                timeoutSeconds: 120
            ),

            // 5. Science passage — genetics and DNA
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                The discovery of DNA's structure in 1953 marked one of the most important breakthroughs in the history of science. James Watson and Francis Crick, working at the Cavendish Laboratory in Cambridge, proposed the double helix model of DNA, building on crucial experimental data from several other scientists. Their model explained how genetic information could be stored, replicated, and transmitted from one generation to the next, opening up entirely new fields of biological research.

                The story of DNA's discovery actually begins much earlier. In 1869, Swiss chemist Friedrich Miescher first isolated a substance he called "nuclein" from white blood cells found in pus-soaked bandages. This substance would later be identified as DNA (deoxyribonucleic acid). In the early 20th century, Phoebus Levene identified the basic components of DNA: the four bases adenine, guanine, cytosine, and thymine, along with a sugar (deoxyribose) and a phosphate group. However, Levene incorrectly proposed the "tetranucleotide hypothesis," suggesting that DNA was a simple repeating unit of equal proportions of these four bases, which led many scientists to dismiss DNA as too simple to carry genetic information.

                The turning point came in 1944 when Oswald Avery, Colin MacLeod, and Maclyn McCarty published their landmark experiment demonstrating that DNA, not protein, was the "transforming principle" responsible for transferring genetic traits between bacteria. Despite the significance of this discovery, many scientists remained skeptical until 1952, when Alfred Hershey and Martha Chase conducted their famous blender experiment using bacteriophages (viruses that infect bacteria). By labeling DNA with radioactive phosphorus-32 and protein with radioactive sulfur-35, they conclusively showed that DNA was the genetic material that entered bacterial cells during infection.

                Meanwhile, Erwin Chargaff made a critical observation that would prove essential for understanding DNA's structure. By carefully analyzing DNA from multiple organisms, he discovered that the amount of adenine always approximately equaled the amount of thymine, and the amount of guanine always approximately equaled the amount of cytosine. These relationships, known as Chargaff's rules, suggested a specific pairing mechanism between the bases, though Chargaff himself did not immediately recognize the structural implications.

                The final piece of the puzzle came from X-ray crystallography work conducted by Rosalind Franklin and Maurice Wilkins at King's College London. Franklin's famous Photograph 51, an X-ray diffraction image of DNA taken in May 1952, provided critical evidence for the helical structure of DNA and allowed key measurements of its dimensions. The photograph revealed that DNA had a helical structure with a diameter of about 20 angstroms and a repeat distance of 34 angstroms, with the bases spaced 3.4 angstroms apart. Watson saw this photograph during a visit to King's College in January 1953, and the dimensional data it provided was instrumental in building the correct model.

                Watson and Crick published their famous paper in Nature on April 25, 1953. The paper, barely more than a page long, described the double helix structure with its two antiparallel sugar-phosphate backbone strands connected by complementary base pairs — adenine paired with thymine via two hydrogen bonds, and guanine paired with cytosine via three hydrogen bonds. Their famous understatement that "it has not escaped our notice that the specific pairing we have postulated immediately suggests a possible copying mechanism for the genetic material" hinted at the enormous implications of their discovery. Watson, Crick, and Wilkins shared the Nobel Prize in Physiology or Medicine in 1962. Rosalind Franklin, who died of ovarian cancer in 1958 at the age of 37, was not eligible for the prize, which is not awarded posthumously.

                Question: What is the name of the famous X-ray photograph that provided critical evidence for DNA's helical structure, and who took it?
                """,
                expectedBehavior: .containsAll(["Photograph 51", "Franklin"]),
                timeoutSeconds: 120
            ),

            // 6. Technology passage — artificial intelligence history
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                The field of artificial intelligence has experienced several cycles of optimism and disappointment since its formal founding. The term "artificial intelligence" was coined by John McCarthy for the Dartmouth Conference in 1956, which is generally considered the birth of AI as an academic discipline. Attendees included McCarthy, Marvin Minsky, Claude Shannon, and Nathaniel Rochester, who proposed that "every aspect of learning or any other feature of intelligence can in principle be so precisely described that a machine can be made to simulate it." The conference was funded by the Rockefeller Foundation with a grant of $7,500.

                Early AI research in the late 1950s and 1960s produced impressive demonstrations that generated enormous enthusiasm. Programs like the Logic Theorist (1956) by Allen Newell, Herbert Simon, and Cliff Shaw could prove mathematical theorems. ELIZA (1966), created by Joseph Weizenbaum at MIT, simulated a Rogerian psychotherapist using simple pattern matching, yet was so convincing that some users formed emotional attachments to it. The General Problem Solver, also by Newell and Simon, attempted to create a universal problem-solving machine. Shakey the Robot, developed at the Stanford Research Institute from 1966 to 1972, was one of the first robots to reason about its own actions.

                However, progress was slower than anticipated. In 1966, a committee chaired by the mathematician John Pierce issued a devastating report on machine translation, concluding that the field had failed to deliver on its promises despite significant government funding. The limitations of early neural networks were highlighted in Minsky and Papert's 1969 book "Perceptrons," which demonstrated that single-layer perceptrons could not solve certain simple problems like the XOR function. These setbacks, combined with the failure to meet overly optimistic predictions, led to the first "AI winter" in the 1970s, during which funding for AI research was dramatically reduced.

                AI experienced a resurgence in the 1980s with the development of expert systems — programs that encoded human expert knowledge in specific domains using if-then rules. Companies like Teknowledge, IntelliCorp, and Applied Intelligence Systems commercialized expert systems technology, and by 1985 the AI industry was generating over $1 billion in annual revenue. XCON (also known as R1), developed by John McDermott at Carnegie Mellon University for Digital Equipment Corporation, was one of the most successful expert systems, configuring VAX computer orders and saving DEC an estimated $40 million per year by the mid-1980s.

                But expert systems also had fundamental limitations. They were brittle, expensive to maintain, and could not learn from experience. When the specialized hardware market collapsed in the late 1980s and companies like Symbolics and Lisp Machines Inc. went bankrupt, AI entered its second winter. DARPA cut funding for AI research, and the Japanese Fifth Generation Computer project, which had aimed to develop intelligent computers using logic programming, was widely viewed as a failure when it concluded in 1992.

                The current AI renaissance began quietly in the 2000s, driven by three converging factors: the availability of massive datasets, dramatic increases in computing power (particularly GPUs), and algorithmic breakthroughs in deep learning. Geoffrey Hinton, Yann LeCun, and Yoshua Bengio — later dubbed the "godfathers of deep learning" — made foundational contributions to neural network architectures and training methods. The watershed moment came in 2012 when Hinton's student Alex Krizhevsky used a deep convolutional neural network called AlexNet to win the ImageNet competition by a dramatic margin, reducing the error rate from 26 percent to 15 percent. This result demonstrated that deep learning could outperform traditional methods on real-world tasks and triggered an explosion of research and investment.

                Question: What was the name of the deep neural network that won the 2012 ImageNet competition, and by how much did it reduce the error rate?
                """,
                expectedBehavior: .containsAll(["AlexNet", "15"]),
                timeoutSeconds: 120
            ),

            // 7. Science passage — plate tectonics
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                The theory of plate tectonics, which explains the large-scale motion of Earth's lithosphere, was one of the most important scientific developments of the 20th century. Although the idea that continents might have once been joined together dates back to at least 1596, when Abraham Ortelius noted the apparent fit of the coastlines of South America and Africa, the modern theory took decades to develop and was not widely accepted by the scientific community until the late 1960s.

                Alfred Wegener, a German meteorologist and geophysicist, proposed the theory of continental drift in 1912. In his book "The Origin of Continents and Oceans," first published in 1915, Wegener argued that all continents had once been joined in a single supercontinent he called Pangaea (meaning "all lands" in Greek), which began to break apart approximately 200 million years ago. Wegener marshaled multiple lines of evidence: the jigsaw-puzzle fit of continental coastlines, matching geological formations on opposite sides of the Atlantic, identical fossil species found on continents separated by vast oceans, and paleoclimatic evidence such as glacial deposits in tropical regions and coal deposits in polar regions.

                Despite this compelling evidence, Wegener's theory was largely rejected by the geological establishment, primarily because he could not propose a convincing mechanism for how continents could plow through the solid oceanic crust. His suggested mechanisms — centrifugal force from Earth's rotation and tidal forces from the Sun and Moon — were quickly shown to be far too weak. Wegener died in 1930 during an expedition on the Greenland ice sheet, his theory still unaccepted by mainstream geology.

                The breakthrough that would eventually validate Wegener's ideas came from an unexpected source: the study of the ocean floor. In the 1950s and 1960s, Harry Hess of Princeton University proposed the theory of sea-floor spreading. Based on sonar mapping of the ocean floor and the discovery of the mid-ocean ridge system, Hess suggested that new oceanic crust was continuously being created at mid-ocean ridges through volcanic activity and was spreading outward on either side. This process provided the missing mechanism for continental drift — continents were not plowing through oceanic crust but rather riding passively on moving plates of lithosphere.

                Further evidence came from the study of magnetic anomalies on the ocean floor. Frederick Vine and Drummond Matthews at Cambridge University showed in 1963 that the pattern of magnetic stripes on the sea floor — alternating bands of normal and reversed polarity running parallel to mid-ocean ridges — was exactly what would be expected if new crust was being created at the ridge and spreading outward, recording the history of geomagnetic reversals. Lawrence Morley independently reached the same conclusion, though his paper was initially rejected by both Nature and the Journal of Geophysical Research, with one reviewer dismissing it as "the sort of thing you'd talk about at a cocktail party."

                The synthesis of these ideas into the comprehensive theory of plate tectonics was largely complete by 1968. Canadian geophysicist J. Tuzo Wilson had introduced the concept of transform faults and the idea that the Earth's surface is divided into rigid plates. Dan McKenzie and Robert Parker formalized the mathematical theory of plate tectonics on a sphere, and Jason Morgan independently developed a similar model. By the early 1970s, plate tectonics had become the unifying paradigm of geology, explaining earthquakes, volcanism, mountain building, and the distribution of fossils and rocks across the globe.

                Question: Who proposed the theory of sea-floor spreading, and at which university was he based?
                """,
                expectedBehavior: .containsAll(["Hess", "Princeton"]),
                timeoutSeconds: 120
            ),

            // 8. Mixed domain passage — coffee history and economics
            EvalPrompt(
                prompt: """
                Read the following passage carefully and answer the question at the end.

                The global coffee industry represents one of the most complex and historically significant commodity trade networks in the world. Coffee is the second most traded commodity by monetary value after crude oil, and the industry supports the livelihoods of an estimated 125 million people worldwide. The story of how a small red berry from the highlands of Ethiopia became one of the world's most consumed beverages spans more than a thousand years and touches on themes of religion, colonialism, revolution, and globalization.

                According to legend, coffee was discovered by an Ethiopian goat herder named Kaldi around 850 CE, who noticed that his goats became unusually energetic after eating berries from a certain wild shrub. While the historicity of this tale is doubtful, it is well established that the coffee plant (Coffea arabica) originated in the highland forests of southwestern Ethiopia, where it still grows wild today. Coffee cultivation and consumption as a beverage likely began in Yemen in the 15th century, where Sufi monks reportedly used it to stay awake during nighttime prayers. The port city of Mocha in Yemen became the primary center for coffee trade, giving its name to the popular chocolate-coffee flavor combination we know today.

                Coffee spread throughout the Ottoman Empire during the 16th century, with the first known coffeehouse opening in Constantinople (modern-day Istanbul) in 1554. These coffeehouses, called "qahveh khaneh," became important social gathering places where men would drink coffee, play chess and backgammon, listen to music, and discuss politics. Ottoman authorities periodically attempted to ban coffeehouses due to their potential as centers of political dissent, with Sultan Murad IV going so far as to order the death penalty for coffee consumption in 1633, though enforcement was sporadic and short-lived.

                European contact with coffee began in earnest in the early 17th century. Venetian merchants first imported coffee beans to Italy around 1615. Pope Clement VIII, when asked to ban coffee as a "Muslim drink," reportedly tasted it and declared it so delicious that it would be a sin to leave it exclusively to non-Christians, and instead gave it papal approval. Coffee quickly spread across Europe, with coffeehouses opening in Oxford (1650), London (1652), Paris (1672), and Vienna (1683). The famous Lloyd's of London insurance market began as a coffeehouse opened by Edward Lloyd in 1688, where ship owners, merchants, and underwriters gathered to conduct business.

                The colonial period transformed coffee from a luxury into a global commodity. The Dutch were the first to successfully cultivate coffee outside of Yemen and Ethiopia, establishing plantations in their colony of Java (in modern-day Indonesia) around 1699. The French brought coffee to their Caribbean colonies in the 1720s, and the Portuguese introduced it to Brazil in 1727. Brazil's coffee industry grew explosively throughout the 19th century, and by 1840, Brazil had become the world's largest coffee producer, a position it maintains to this day. At its peak, coffee accounted for more than 70 percent of Brazil's export revenue, and the Brazilian economy was so dependent on coffee that the Portuguese phrase "café com leite" (coffee with milk) was used to describe the political alliance between the coffee-producing state of São Paulo and the dairy-farming state of Minas Gerais.

                The development of instant coffee in the 20th century further democratized coffee consumption. While several inventors had experimented with soluble coffee, the modern process was perfected by Nestlé, which introduced Nescafé in 1938. The product became enormously popular during World War II, when the US military included instant coffee in soldiers' ration kits. In the post-war era, the specialty coffee movement emerged as a reaction against the perceived decline in coffee quality. The "first wave" of coffee referred to the mass-market commodity coffee of companies like Folgers and Maxwell House. The "second wave," exemplified by Starbucks (founded in 1971 in Seattle's Pike Place Market), emphasized higher-quality beans and the coffeehouse experience. The "third wave," which emerged in the 2000s, treats coffee as an artisanal craft product, with emphasis on single-origin beans, direct trade relationships with farmers, and precise brewing methods.

                Question: In what year did the Dutch establish coffee plantations in Java, and in what year did Brazil become the world's largest coffee producer?
                """,
                expectedBehavior: .containsAll(["1699", "1840"]),
                timeoutSeconds: 120
            ),
        ],
        isBuiltIn: true
    )
}
