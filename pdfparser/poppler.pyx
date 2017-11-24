# This file is part of pdfparser.
#
# pdfparse is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# pdfparser is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with pdfparser.  If not, see <http://www.gnu.org/licenses/>.
#
# Original version by Ivan Zderadicka  (https://github.com/izderadicka/pdfparser)
# Adopted and modified by Rossum (https://github.com/rossumai/pdfparser)

from libcpp cimport bool
from cpython cimport bool as PyBool
from cpython.object cimport Py_EQ, Py_NE

ctypedef bool GBool

DEF PRECISION=1e-6


cdef extern from "GlobalParams.h":
    GlobalParams *globalParams
    cdef cppclass GlobalParams:
        pass

 # we need to init globalParams - just one during program run
globalParams = new GlobalParams()


cdef extern from "goo/GooString.h":
    cdef cppclass GooString:
        GooString(const char *sA)
        int getLength()
        char *getCString()
        char getChar(int i)


cdef extern from "OutputDev.h":
    cdef cppclass OutputDev:
        pass


cdef extern from 'Annot.h':
    cdef cppclass Annot:
        pass


cdef extern from 'Gfx.h':
    cdef cppclass Gfx:
        pass


cdef extern from 'XRef.h':
    cdef cppclass XRef:
        pass


cdef extern from "PDFDoc.h":
    cdef cppclass PDFDoc:
        GBool isOk()
        int getErrorCode()
        int getNumPages()
        void displayPageSlice(OutputDev *out, int page, double hDPI, double vDPI,
                              int rotate, GBool useMediaBox, GBool crop, GBool printing,
                              int sliceX, int sliceY, int sliceW, int sliceH,
                              GBool (*abortCheckCbk)(void *data) = NULL,
                              void *abortCheckCbkData = NULL,
                              GBool (*annotDisplayDecideCbk)(Annot *annot, void *user_data) = NULL,
                              void *annotDisplayDecideCbkData = NULL, GBool copyXRef = False)
        double getPageMediaWidth(int page)
        double getPageMediaHeight(int page)
        Page *getPage(int page);


cdef extern from "Page.h":
    cdef cppclass PDFRectangle:
        double x1, y1, x2, y2;

    cdef cppclass Page:
        Gfx *createGfx(OutputDev *out, double hDPI, double vDPI,
                       int rotate, GBool useMediaBox, GBool crop,
                       int sliceX, int sliceY, int sliceW, int sliceH, GBool printing,
                       GBool (*abortCheckCbk)(void *data),
                       void *abortCheckCbkData, XRef *xrefA = NULL)
        void display(Gfx *gfx)
        PDFRectangle *getCropBox()

cdef extern from "PDFDocFactory.h":
    cdef cppclass PDFDocFactory:
        PDFDocFactory()
        PDFDoc *createPDFDoc(const GooString &uri, GooString *ownerPassword = NULL,
                             GooString *userPassword = NULL, void *guiDataA = NULL)


cdef extern from "TextOutputDev.h":
    cdef cppclass TextOutputDev:
        TextOutputDev(char *fileName, GBool physLayoutA,
        double fixedPitchA, GBool rawOrderA, GBool append)
        TextPage *takeText()

    cdef cppclass TextPage:
        void incRefCnt()
        void decRefCnt()
        TextFlow *getFlows()
        GooString *getText(double xMin, double yMin, double xMax, double yMax);

    cdef cppclass TextFlow:
        TextFlow *getNext()
        TextBlock *getBlocks()

    cdef cppclass TextBlock:
        TextBlock *getNext()
        TextLine *getLines()
        void getBBox(double *xMinA, double *yMinA, double *xMaxA, double *yMaxA)

    cdef cppclass TextLine:
        TextWord *getWords()
        TextLine *getNext()

    cdef cppclass TextWord:
        TextWord *getNext()
        int getLength()
        GooString *getText()
        void getBBox(double *xMinA, double *yMinA, double *xMaxA, double *yMaxA)
        void getCharBBox(int charIdx, double *xMinA, double *yMinA, double *xMaxA, double *yMaxA)
        GBool hasSpaceAfter  ()
        TextFontInfo *getFontInfo(int idx)
        GooString *getFontName(int idx)
        double getFontSize()
        void getColor(double *r, double *g, double *b)

    cdef cppclass TextFontInfo:
        GooString *getFontName() 
        double getAscent();
        double getDescent();

        GBool isFixedWidth() 
        GBool isSerif() 
        GBool isSymbolic() 
        GBool isItalic() 
        GBool isBold() 


cdef extern from "cairo.h":
    cdef struct _cairo:
        pass
    ctypedef _cairo cairo_t

    void cairo_save (cairo_t *cr)
    void cairo_restore (cairo_t *cr)


cdef extern from "pycairo.h":
    ctypedef struct PycairoContext:
        cairo_t *ctx;


cdef extern from "CairoFontEngine.h":
    cdef cppclass CairoFontEngine:
        pass


cdef extern from "CairoOutputDev.h":
    cdef cppclass CairoImage:
        void getRect(double *x1, double *y1, double *x2, double *y2)

    cdef cppclass CairoImageOutputDev:
        CairoImageOutputDev()
        CairoImage *getImage(int i)
        int getNumImages()

    cdef cppclass CairoOutputDev:
        CairoOutputDev()
        void setCairo(cairo_t *cr)
        void startDoc(PDFDoc *docA, CairoFontEngine *parentFontEngine)


ERROR_CODE_MESSAGES = {0: 'no error',
                       1: "couldn't open the PDF file",
                       2: "couldn't read the page catalog",
                       3: "PDF file was damaged and couldn't be repaired",
                       4: 'file was encrypted and password was incorrect or not supplied',
                       5: 'nonexistent or invalid highlight file',
                       6: 'invalid printer',
                       7: 'error during printing',
                       8: "PDF file doesn't allow that operation",
                       9: 'invalid page number',
                       10: 'file I/O error'}


cdef class PopplerDocument:
    cdef PDFDoc *document

    # Maintain (as best as possible) the original physical layout
    # of the text. The default is to ´undo' physical layout (columns,
    # hyphenation, etc.) and output the text in reading order.
    cdef PyBool keep_physical_layout

    # Assume fixed-pitch (or tabular) text, with the specified
    # character width (in points). This forces physical layout
    # mode.
    cdef double fixed_pitch

    cdef void render_page_into_device(self, OutputDev *device, int page_number, double hDPI=72,
                                      double vDPI=72, GBool printing=False, GBool crop=False,
                                      int sliceX=-1, int sliceY=-1, int sliceW=-1, int sliceH=-1):
        self.document.displayPageSlice(device, page_number + 1, hDPI, vDPI, 0, True, crop, printing,
                                       sliceX, sliceY, sliceW, sliceH)

    cdef object get_page_size(self, page_number):
        cdef double width = self.document.getPageMediaWidth(page_number + 1)
        cdef double height = self.document.getPageMediaHeight(page_number + 1)
        return (width, height)

    def get_images_bboxes(self, page_number):
        cdef CairoImageOutputDev *image_device = new CairoImageOutputDev()
        cdef Page *page = self.document.getPage(page_number + 1)

        cdef Gfx *gfx = page.createGfx(<OutputDev *> image_device, 72.0, 72.0, 0, False, True, -1, -1, -1, -1, False, NULL, NULL)
        cdef CairoImage *image
        cdef double x1, x2, y1, y2
        cdef int i
        cdef list images_bboxes = []

        page.display(gfx)
        del gfx

        for i in range(image_device.getNumImages()):
            image = image_device.getImage(i)
            image.getRect(&x1, &y1, &x2, &y2);

            x1 -= page.getCropBox().x1;
            y1 -= page.getCropBox().y1;
            x2 -= page.getCropBox().x1;
            y2 -= page.getCropBox().y1;

            images_bboxes.append(BBox(x1, y1, x2, y2))

        del image_device

        return images_bboxes

    def __cinit__(self, char *filename, PyBool keep_physical_layout=False, double fixed_pitch=0.0):
        self.document = PDFDocFactory().createPDFDoc(GooString(filename))
        if not self.document.isOk():
            error_code = self.document.getErrorCode()
            del self.document
            self.document = NULL
            raise RuntimeError('could not open document %s (error code: %d, message: %s)'
                               % (filename, error_code, ERROR_CODE_MESSAGES.get(error_code, 'none')))
        self.keep_physical_layout = keep_physical_layout
        self.fixed_pitch = fixed_pitch

    def __dealloc__(self):
        if self.document != NULL:
            del self.document

    def page_count(self):
        return self.document.getNumPages()

    def __iter__(self):
        return DocumentPageIterator(self)

    def get_page(self, int page_number):
        return PopplerPage(self, page_number)

    def render_page(self, context, page_number, hDPI=72.0, vDPI=72.0, printing=False, crop=None):
        '''
        Render a page into `cairo.Context` with the given resolution.

        Parameters
        ----------
        context : cairo.Context
            The cairo context into which the page is rendered.

        page_number : int
            The index of the page to render.

        hDPI : float
            The horizontal resolution to render the page with.

        vDPI : float
            The vertical resolution to render the page with.

        printing : bool
            Set the rendering into printing mode.

        crop : tuple of int or None
            If not None, only the specified rectangular region from the page
            is rendered, otherwise, the whole page is rendered. The format
            of crop is (left, top, bottom, right).
        '''
        # See https://www.cairographics.org/cookbook/renderpdf/
        cdef CairoOutputDev *device
        cdef cairo_t *cairo
        cdef int sliceX = -1, sliceY = -1, sliceW = -1, sliceH = -1

        cairo = (<PycairoContext *> context).ctx

        if crop is not None:
            sliceX, sliceY, sliceW, sliceH = crop
            # (right, bottom) -> (width, height)
            sliceW -= sliceX
            sliceH -= sliceY
            # scale
            sliceX *= hDPI / 72.0
            sliceY *= vDPI / 72.0
            sliceW *= hDPI / 72.0
            sliceH *= vDPI / 72.0

        # See poppler/glib/poppler-document.cc:134-135 - creation of CairoOutputDev for a document
        device = new CairoOutputDev()
        device.startDoc(self.document, NULL)

        # See poppler/glib/poppler-page.cc:341-343 - setting of CairoOutputDev before a page is rendered
        device.setCairo(cairo)
        cairo_save(cairo)
        self.render_page_into_device(<OutputDev *> device, page_number, hDPI, vDPI, printing,
                                     crop is not None, sliceX, sliceY, sliceW, sliceH)
        cairo_restore(cairo)

        del device


cdef class DocumentPageIterator:
    cdef:
        PopplerDocument document
        int page_number

    def __cinit__(self, PopplerDocument document):
        self.document = document
        self.page_number = -1

    def __next__(self):
        self.page_number += 1
        if self.page_number >= self.document.page_count():
            raise StopIteration()
        return self.document.get_page(self.page_number)


cdef class PopplerPage:
    cdef:
        PopplerDocument document
        int page_number
        TextPage *page

    def __cinit__(self, PopplerDocument document, int page_number):
        cdef TextOutputDev * device

        device = new TextOutputDev(NULL, document.keep_physical_layout, document.fixed_pitch, False, False);
        document.render_page_into_device(<OutputDev *> device, page_number)
        self.page = device.takeText()
        del device

        self.document = document
        self.page_number = page_number

    def __dealloc__(self):
        if self.page != NULL:
            # This frees any potential flows/blocks/lines/
            self.page.decRefCnt()

    def __iter__(self):
        return FlowsIterator(self)

    def render(self, context, hDPI=72.0, vDPI=72.0, printing=False, crop=None):
        '''
        Render a page into `cairo.Context` with the given resolution.

        Parameters
        ----------
        context : cairo.Context
            The cairo context into which the page is rendered.

        hDPI : float
            The horizontal resolution to render the page with.

        vDPI : float
            The vertical resolution to render the page with.

        printing : bool
            Set the rendering into printing mode.

        crop : tuple of int or None
            If not None, only the specified rectangular region from the page
            is rendered, otherwise, the whole page is rendered. The format
            of crop is (left, top, bottom, right).
        '''
        self.document.render_page(context, self.page_number, hDPI, vDPI, printing, crop)

    def get_images_bboxes(self):
        return self.document.get_images_bboxes(self.page_number)

    property page_number:
        '''
        The page number within the document containing it.
        '''
        def __get__(self):
            return self.page_number

    property size:
        '''
        The size of the page as (width, height).
        '''
        def __get__(self):
            return self.document.get_page_size(self.page_number)

    cdef TextFlow *getFlows(self):
        return self.page.getFlows()

    def get_text(self, bbox=None):
        cdef GooString *text

        if bbox is None:
            left, top = 0, 0
            right, bottom = self.size
        else:
            left, top, right, bottom = bbox
        
        text = self.page.getText(left, top, right, bottom)
        result = text.getCString().decode('UTF-8')
        del text

        return result


cdef class FlowsIterator:
    cdef PopplerPage page
    cdef TextFlow *flows

    def __cinit__(self, PopplerPage page):
        self.page = page
        self.flows = page.getFlows()

    def __next__(self):
        cdef Flow flow

        if not self.flows:
            raise StopIteration()

        flow = Flow(self.page).wrap(self.flows)
        self.flows = self.flows.getNext()
        return flow


cdef class Flow:
    cdef PopplerPage page
    cdef TextFlow *flow

    def __cinit__(self, PopplerPage page):
        self.page = page
        self.flow = NULL

    cdef Flow wrap(self, TextFlow *flow):
        self.flow = flow
        return self

    cdef TextBlock *getBlocks(self):
        if self.flow:
            return self.flow.getBlocks()
        else:
            return NULL

    def __iter__(self):
        return BlocksIterator(self.page, self)


cdef class BlocksIterator:
    cdef PopplerPage page
    cdef TextBlock *blocks

    def __cinit__(self, PopplerPage page, Flow flow):
        self.page = page
        self.blocks = flow.getBlocks()

    def __next__(self):
        cdef Block block

        if not self.blocks:
            raise StopIteration()

        block = Block(self.page).wrap(self.blocks)
        self.blocks = self.blocks.getNext()
        return block


cdef class Block:
    cdef PopplerPage page
    cdef TextBlock *block

    def __cinit__(self, PopplerPage page):
        self.page = page
        self.block = NULL

    cdef Block wrap(self, TextBlock *block):
        self.block = block
        return self

    cdef TextLine *getLines(self):
        if self.block:
            return self.block.getLines()
        else:
            return NULL

    def __iter__(self):
        return LinesIterator(self.page, self)

    property bbox:
        '''
        The bounding box of this block of text
        as (left, top, right, bottom).
        '''
        def __get__(self):
            cdef double x1, y1, x2, y2
            self.block.getBBox(&x1, &y1, &x2, &y2)
            return BBox(x1,y1,x2,y2)


cdef class LinesIterator:
    cdef PopplerPage page
    cdef TextLine *lines

    def __cinit__(self, PopplerPage page, Block block):
        self.page = page
        self.lines = block.getLines()

    def __next__(self):
        cdef Line line

        if not self.lines:
            raise StopIteration()

        line = Line(self.page).wrap(self.lines)
        self.lines = self.lines.getNext()
        return line


cdef class Line:
    cdef:
        PopplerPage page
        TextLine *line
        double x1, y1, x2, y2
        unicode _text
        list _bboxes
        CompactList _fonts

    def __cinit__(self, PopplerPage page):
        self.page = page
        self.line = NULL

    cdef Line wrap(self, TextLine *line):
        self.line = line
        self._text = u'' # text bytes
        self.x1 = 0
        self.y1 = 0
        self.x2 = 0
        self.y2 = 0
        self._bboxes = []
        self._fonts = CompactList()
        self._get_text()
        return self

    def _get_text(self):
        cdef:
            TextWord *word
            GooString *s
            double bx1, bx2, by1, by2
            list words = []
            int i, word_length
            BBox last_bbox
            FontInfo last_font
            double r, g, b

        word = self.line.getWords()

        while word:
            word_length = word.getLength()
            assert word_length > 0

            # gets bounding boxes for all characters and font info
            for i in range(word_length):
                word.getCharBBox(i, &bx1, &by1, &bx2, &by2)

                last_bbox = BBox(bx1, by1, bx2, by2)

                # if previous word is space update it's right end
                if i == 0 and words and words[-1] == u' ':
                    self._bboxes[-1].x2 = last_bbox.x1

                self._bboxes.append(last_bbox)

                word.getColor(&r, &g, &b)

                last_font = FontInfo(word.getFontName(i).getCString().decode('UTF-8'),
                                     word.getFontSize(),
                                     Color(r, g, b))

                self._fonts.append(last_font)

            s = word.getText()
            words.append(s.getCString().decode('UTF-8'))
            del s

            # the number of bboxes/fonts must equal the number of characters in the word
            assert len(words[-1]) == word_length

            # update the line bounding box
            word.getBBox(&bx1, &by1, &bx2, &by2)

            if bx1 < self.x1 or self.x1 == 0:
                self.x1 = bx1

            if by1 < self.y1 or self.y1 == 0:
                self.y1 = by1

            if bx2 > self.x2:
                self.x2 = bx2

            if by2 > self.y2:
                self.y2 = by2

            # add space after word if necessary
            if word.hasSpaceAfter():
                words.append(u' ')
                self._bboxes.append(BBox(last_bbox.x2, last_bbox.y1, last_bbox.x2, last_bbox.y2))
                self._fonts.append(last_font)

            # continue with the next word in the line
            word = word.getNext()

        self._text= u''.join(words)

        # the number of bboxes/fonts must equal the number of characters in the word
        assert len(self._bboxes) == len(self._text)

    property bbox:
        '''
        The bounding box of this line of text
        as (left, top, right, bottom).
        '''
        def __get__(self):
            return BBox(self.x1, self.y1, self.x2, self.y2)

    property text:
        def __get__(self):
            return self._text

    property char_bboxes:
        def __get__(self):
            return self._bboxes

    property char_fonts:
        def __get__(self):
            return self._fonts


cdef class BBox:
    cdef double x1, y1, x2, y2

    def __cinit__(self, double x1, double y1, double x2, double y2 ):
        self.x1 = x1
        self.x2 = x2
        self.y1 = y1
        self.y2 = y2

    def as_tuple(self):
        return self.x1, self.y1, self.x2, self.y2

    def __getitem__(self, i):
        if i == 0:
            return self.x1
        elif i == 1:
            return self.y1
        elif i == 2:
            return self.x2
        elif i == 3:
            return self.y2
        raise IndexError()

    property x1:
        def __get__(self):
            return self.x1

        def __set__(self, double value):
            self.x1 = value

    property x2:
        def __get__(self):
            return self.x2

        def __set__(self, double value):
            self.x2 = value

    property y1:
        def __get__(self):
            return self.y1

        def __set__(self, double value):
            self.y1 = value
            
    property y2:
        def __get__(self):
            return self.y2

        def __set__(self, double value):
            self.y2 = value


cdef class Color:
    cdef:
        double r, b, g

    def __cinit__(self, double r, double g, double b):
        self.r = r
        self.g = g
        self.b = b

    def as_tuple(self):
        return self.r, self.g, self.b

    property r:
        def __get__(self):
            return self.r

    property g:
        def __get__(self):
            return self.g

    property b:
        def __get__(self):
            return self.b

    def __str__(self):
        return 'r:%0.2f g:%0.2f, b:%0.2f' % self.as_tuple()

    def __richcmp__(x, y, op):
        if isinstance(x, Color) and isinstance(y, Color) and (op == Py_EQ or op == Py_NE):
            eq = abs(x.r - y.r) < PRECISION and \
                 abs(x.g - y.g) < PRECISION and \
                 abs(x.b - y.b) < PRECISION
            return eq if op == Py_EQ else not eq
        return NotImplemented


cdef class FontInfo:
    cdef:
        unicode name
        double size
        Color color

    def __cinit__(self, unicode name, double size, Color color):
        nparts = name.split('+', 1)
        self.name = nparts[-1]
        self.size = size
        self.color = color

    property name:
        def __get__(self):
            return self.name

        def __set__(self, unicode value):
            self.name = value

    property size:
        def __get__(self):
            return self.size

        def __set__(self, double value):
            self.size = value

    property color:
        def __get__(self):
            return self.color

        def __set__(self, Color value):
            self.color = value

    def __richcmp__(x, y, op):
        if isinstance(x, FontInfo) and isinstance(y, FontInfo) and (op == Py_EQ or op == Py_NE):
            eq = x.name == y.name and \
                 abs(x.size - y.size) < PRECISION and \
                 x.color == y.color
            return eq if op == Py_EQ else not eq
        return NotImplemented


cdef class CompactListIterator:
    cdef:
        list index
        list items
        int i

    def __cinit__(self, list index, list items):
        self.i = 0
        self.index = index
        self.items = items

    def __next__(self):
        if self.i >= len(self.index):
            raise StopIteration()

        item = self.items[self.index[self.i]]
        self.i += 1
        return item


cdef class CompactList:
    # CompactList stores immutable items in more memory-efficient manner. i-th item in the list
    # is actually represented by index[i]-th item. When a group of equal items is added then
    # only the first is actually stored and the rest of items use just the index to refer to it.
    cdef:
        list index
        list items

    def __init__(self):
        self.index=[]
        self.items=[]

    def append(self, item):
        cdef long last

        last = len(self.items) - 1

        if last >= 0 and self.items[last] == item:
            self.index.append(last)
        else:
            self.items.append(item)
            self.index.append(last + 1)

    def __getitem__(self, i):
        return self.items[self.index[i]]

    def __len__(self):
        return len(self.index)

    def __iter__(self):
        return CompactListIterator(self.index, self.items)

    property compactness:
        '''
        The actual fraction of the items that have been added
        to the list and needed to be stored.
        '''
        def __get__(self):
            return float(len(self.items)) / len(self.index)
